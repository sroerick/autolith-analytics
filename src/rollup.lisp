;;;; rollup.lisp --- spend rollups per day / per model / per actor.

(in-package #:autolith-analytics)

(defstruct bucket
  (events 0) (requests 0) (tokens-in 0) (tokens-out 0) (cached-tokens 0) (wall 0))

(defun display-kind (kind)
  "Unknown kinds display as other until the reader learns them."
  (if (member kind *known-kinds* :test #'string=) kind "other"))

(defun add-event (bucket event)
  (incf (bucket-events bucket))
  (incf (bucket-requests bucket) (or (getf event :requests) 0))
  (incf (bucket-tokens-in bucket) (or (getf event :tokens-in) 0))
  (incf (bucket-tokens-out bucket) (or (getf event :tokens-out) 0))
  (incf (bucket-cached-tokens bucket) (or (getf event :cached-tokens) 0))
  (incf (bucket-wall bucket) (or (getf event :wall-s) 0)))

(defun bump (table key event)
  (add-event (or (gethash key table)
                 (setf (gethash key table) (make-bucket)))
             event))

(defun day-of (event)
  "UTC day from the ISO-8601 ts."
  (subseq (getf event :ts) 0 10))

(defun wall-json (wall)
  (if (zerop wall) 0 (/ (round (* 100 wall)) 100.0d0)))

(defun bucket-json (bucket &rest identity)
  (apply #'jobj
         (append identity
                 (list "events" (bucket-events bucket)
                       "requests" (bucket-requests bucket)
                       "tokens_in" (bucket-tokens-in bucket)
                       "tokens_out" (bucket-tokens-out bucket)
                       "cached_tokens" (bucket-cached-tokens bucket)
                       "wall_s" (wall-json (bucket-wall bucket))))))

(defun hash-pairs (table)
  (loop for key being the hash-keys of table using (hash-value value)
        collect (cons key value)))

(defun rows (pairs key-name day-p)
  "JSON array of bucket objects: days ascending, everything else by request
then token weight descending."
  (let ((sorted
          (if day-p
              (sort (copy-list pairs) #'string< :key #'car)
              (sort (copy-list pairs)
                    (lambda (a b)
                      (let ((ra (bucket-requests (cdr a)))
                            (rb (bucket-requests (cdr b))))
                        (if (/= ra rb)
                            (> ra rb)
                            (let ((ia (bucket-tokens-in (cdr a)))
                                  (ib (bucket-tokens-in (cdr b))))
                              (if (/= ia ib)
                                  (> ia ib)
                                  (string< (car a) (car b)))))))))))
    (mapcar (lambda (pair) (bucket-json (cdr pair) key-name (car pair)))
            sorted)))

(defun rollup (snap)
  "Roll a snapshot up into totals, per day, per model, per actor, and kind counts."
  (let ((totals (make-bucket))
        (by-day (make-hash-table :test #'equal))
        (by-model (make-hash-table :test #'equal))
        (by-actor (make-hash-table :test #'equal))
        (by-kind (make-hash-table :test #'equal)))
    (dolist (event (snapshot-events snap))
      (add-event totals event)
      (bump by-day (day-of event) event)
      (bump by-model (or (getf event :model) "unknown") event)
      (bump by-actor (getf event :actor) event)
      (incf (gethash (display-kind (getf event :kind)) by-kind 0)))
    (jobj
     "generated" (snapshot-generated snap)
     "events" (length (snapshot-events snap))
     "malformed" (snapshot-malformed snap)
     "totals" (bucket-json totals)
     "by_day" (rows (hash-pairs by-day) "day" t)
     "by_model" (rows (hash-pairs by-model) "model" nil)
     "by_actor" (rows (hash-pairs by-actor) "actor" nil)
     "kinds" (apply #'jobj
                    (loop for (kind . count) in (hash-pairs by-kind)
                          collect kind collect count)))))
