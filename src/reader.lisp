;;;; reader.lisp --- parse append-only JSONL event files (docs/schema-v1.md).

(in-package #:autolith-analytics)

(defparameter *known-kinds* '("llm-usage" "run-step" "message"))

(defparameter *max-string* 200
  "Hygiene cap from the schema: the reader refuses lines carrying more than
this much string content in any field, note included.")

(defstruct snapshot
  (events nil :type list)        ; canonical event plists, oldest first
  (malformed 0)                  ; lines refused: bad json, missing fields, hygiene
  (files nil :type list)         ; event file base names that were read
  (generated nil :type (or null string))
  (fingerprint nil))             ; internal cache key

(defun jobj (&rest pairs)
  "Build a JSON object (string-keyed hash table) from alternating key/value pairs."
  (let ((table (make-hash-table :test #'equal)))
    (loop for (k v) on pairs by #'cddr
          do (setf (gethash k table) v))
    table))

(defun json-key (keyword)
  "Map an event plist keyword (:tokens-in) to its schema key (tokens_in)."
  (substitute #\_ #\- (string-downcase (symbol-name keyword))))

(defun iso-now ()
  (multiple-value-bind (sec min hour day month year)
      (get-decoded-time)
    (format nil "~4d-~2,'0d-~2,'0dT~2,'0d:~2,'0d:~2,'0dZ"
            year month day hour min sec)))

(defun source-from-name (name)
  "Source id from a file base name, stripping an optional -YYYYMMDD rotation
suffix. The reader must handle both <source>.jsonl and rotated patterns."
  (let ((len (length name)))
    (if (and (> len 9)
             (char= (char name (- len 9)) #\-)
             (every #'digit-char-p (subseq name (- len 8))))
        (subseq name 0 (- len 9))
        name)))

(defun event-files (dir)
  "Sorted list of .jsonl pathnames under DIR; missing DIR yields nothing."
  (sort (directory (merge-pathnames "*.jsonl" dir))
        #'string< :key #'namestring))

(defun valid-string (value)
  (and (stringp value) (plusp (length value)) (<= (length value) *max-string*)))

(defun valid-count (value)
  (and (integerp value) (>= value 0)))

(defun hygiene-violation (obj)
  "Reason string when OBJ carries oversized strings or non-scalar unknown
fields; NIL when clean. Unknown fields may appear and are ignored, but free
text beyond the cap is refused regardless of field."
  (loop for key being the hash-keys of obj
          using (hash-value value)
        do (cond
             ((and (stringp value) (> (length value) *max-string*))
              (return (format nil "string field ~a exceeds ~a chars"
                              key *max-string*)))
               ((and (not (stringp value))
                     (or (listp value) (hash-table-p value) (vectorp value)))
                (return (format nil "field ~a is not a scalar" key)))
             (t nil))))

(defun parse-event (line)
  "Parse one JSONL line into a canonical event plist, or (values nil reason)."
  (labels ((fail (reason) (return-from parse-event (values nil reason))))
    (let ((obj (handler-case (yason:parse line)
                 (error (e) (fail (format nil "bad json: ~a" e))))))
      (unless (hash-table-p obj) (fail "line is not a json object"))
      (let ((reason (hygiene-violation obj)))
        (when reason (fail reason)))
      (let ((ts (gethash "ts" obj))
            (schema-v (gethash "schema_v" obj))
            (source (gethash "source" obj))
            (kind (gethash "kind" obj))
            (actor (gethash "actor" obj))
            (dir (gethash "dir" obj))
            (wall-s (gethash "wall_s" obj)))
        (unless (and (stringp ts) (>= (length ts) 10)) (fail "ts missing or short"))
        (unless (and (integerp schema-v) (= schema-v 1)) (fail "schema_v must be 1"))
        (unless (valid-string source) (fail "source missing or oversized"))
        (unless (valid-string kind) (fail "kind missing or oversized"))
        (unless (valid-string actor) (fail "actor missing or oversized"))
        (unless (or (null dir)
                    (member dir '("in" "out") :test #'string=))
          (fail "dir must be in or out"))
        (unless (or (null wall-s) (numberp wall-s)) (fail "wall_s must be a number"))
          (dolist (count '("tokens_in" "tokens_out" "cached_tokens" "requests"))
            (unless (or (null (gethash count obj))
                        (valid-count (gethash count obj)))
              (fail (format nil "~a must be a non-negative integer" count))))
        (dolist (text '("model" "run_id" "ref" "note"))
          (let ((value (gethash text obj)))
            (unless (or (null value) (and (stringp value)
                                          (<= (length value) *max-string*)))
              (fail (format nil "~a must be a string of at most ~a chars"
                            text *max-string*)))))
        (values
         (list :ts ts
               :schema-v schema-v
               :source source
               :kind kind
               :actor actor
               :model (gethash "model" obj)
               :tokens-in (gethash "tokens_in" obj)
               :tokens-out (gethash "tokens_out" obj)
               :cached-tokens (gethash "cached_tokens" obj)
               :requests (gethash "requests" obj)
               :wall-s wall-s
               :run-id (gethash "run_id" obj)
               :ref (gethash "ref" obj)
               :dir dir
               :note (gethash "note" obj))
         nil)))))

(defun read-file-events (path)
  "Return (values events malformed-count) for one event file."
  (let ((events ()) (malformed 0))
    (with-open-file (in path :if-does-not-exist nil)
      (when in
        (loop for line = (read-line in nil)
              while line
              do (let ((trimmed (string-trim '(#\space #\tab #\return) line)))
                   (when (plusp (length trimmed))
                     (multiple-value-bind (event reason) (parse-event trimmed)
                       (declare (ignore reason))
                       (if event (push event events) (incf malformed))))))))
    (values (nreverse events) malformed)))

(defun fingerprint (dir)
  "Cache key: name, write-date, and size of every event file."
  (mapcar (lambda (path)
            (list (namestring path)
                  (file-write-date path)
                  (with-open-file (in path) (file-length in))))
          (event-files dir)))

(defun load-snapshot (&optional (dir *events-dir*))
  "Scan DIR and build a fresh snapshot. Files are read name-sorted, which is
chronological for the rotated pattern; append order is kept within a file."
  (let ((events ()) (malformed 0) (files ()))
    (dolist (path (event-files dir))
      (push (source-from-name (pathname-name path)) files)
      (multiple-value-bind (file-events file-malformed)
          (read-file-events path)
          (setf events (append events (nreverse file-events)))
        (incf malformed file-malformed)))
    (make-snapshot :events events
                   :malformed malformed
                   :files (nreverse files)
                   :generated (iso-now)
                   :fingerprint (fingerprint dir))))

(defvar *cache-lock* (bt:make-lock "snapshot-cache"))
(defvar *cached-snapshot* nil)

(defun snapshot ()
  "Current snapshot; rescans only when the event files changed."
  (bt:with-lock-held (*cache-lock*)
    (let ((fp (fingerprint *events-dir*)))
      (unless (and *cached-snapshot*
                   (equal fp (snapshot-fingerprint *cached-snapshot*)))
        (setf *cached-snapshot* (load-snapshot *events-dir*)))
      *cached-snapshot*)))

(defun event-json (event)
  "Canonical event plist to a JSON object with schema keys."
  (apply #'jobj
         (loop for (k v) on event by #'cddr
               when v
                 nconc (list (json-key k) v))))
