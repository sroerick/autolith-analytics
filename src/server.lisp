;;;; server.lisp --- a small threaded HTTP server: one HTML pane plus a JSON API.

(in-package #:autolith-analytics)

;;; --- routing ---

(defstruct route method path handler)

(defparameter *routes* nil)

(defun register-route (method path handler)
  (setf *routes*
        (remove-if (lambda (route)
                     (and (eq (route-method route) method)
                          (string= (route-path route) path)))
                   *routes*))
  (push (make-route :method method :path path :handler handler) *routes*))

(defmacro defroute (method path (query) &body body)
  `(register-route ,method ,path (lambda (,query) ,@body)))

;;; --- handlers: each returns (values body content-type status) ---

(defroute :get "/" (query)
  (declare (ignore query))
  (values (pane-html) "text/html; charset=utf-8" 200))

(defroute :get "/api/rollup" (query)
  (declare (ignore query))
  (values (with-output-to-string (out)
            (yason:encode (rollup (snapshot)) out))
          "application/json; charset=utf-8" 200))

(defroute :get "/api/events" (query)
  (let* ((limit (or (cdr (assoc "limit" query :test #'string=)) "200"))
         (limit (max 1 (min (or (ignore-errors (parse-integer limit :junk-allowed t)) 200)
                            1000))))
    (values (with-output-to-string (out)
              (yason:encode (mapcar #'event-json
                                    (last (snapshot-events (snapshot)) limit))
                            out))
            "application/json; charset=utf-8" 200)))

(defroute :get "/api/health" (query)
  (declare (ignore query))
  (let ((snap (snapshot)))
    (values (with-output-to-string (out)
              (yason:encode (jobj "ok" t
                                  "events" (length (snapshot-events snap))
                                  "malformed" (snapshot-malformed snap)
                                  "files" (snapshot-files snap))
                            out))
            "application/json; charset=utf-8" 200)))

;;; --- wire reading ---

(defun trim (string)
  (string-trim '(#\space #\tab #\return) string))

(defun read-request-head (stream)
  "Return (values method target headers) or NIL when the client hangs up
before sending a request line."
  (let ((request-line (and (peek-char nil stream nil nil)
                           (read-line stream nil))))
    (when request-line
      (let ((parts (uiop:split-string (trim request-line) :separator " ")))
        (when (>= (length parts) 3)
          (let ((headers ()))
            (loop for line = (read-line stream nil)
                  while (and line (string/= (trim line) ""))
                  do (let ((colon (position #\: line)))
                       (when colon
                         (push (cons (string-downcase (trim (subseq line 0 colon)))
                                     (trim (subseq line (1+ colon))))
                               headers))))
            (values (first parts) (second parts) (nreverse headers))))))))

(defun percent-decode (string)
  (with-output-to-string (out)
    (loop with length = (length string)
          for index = 0 then (1+ index)
          while (< index length)
          do (let ((ch (char string index)))
               (cond
                 ((and (char= ch #\%)
                       (< (+ index 2) length)
                       (digit-char-p (char string (1+ index)) 16)
                       (digit-char-p (char string (+ index 2)) 16))
                  (write-char (code-char (+ (* 16 (digit-char-p (char string (1+ index)) 16))
                                            (digit-char-p (char string (+ index 2)) 16)))
                              out)
                  (incf index 2))
                 ((char= ch #\+) (write-char #\space out))
                 (t (write-char ch out)))))))

(defun parse-query (string)
  (when string
    (loop for pair in (uiop:split-string string :separator "&")
          for equals = (position #\= pair)
          when equals
            collect (cons (percent-decode (subseq pair 0 equals))
                          (percent-decode (subseq pair (1+ equals)))))))

;;; --- writing ---

(defun status-reason (code)
  (case code
    (200 "OK") (400 "Bad Request") (404 "Not Found") (405 "Method Not Allowed")
    (500 "Internal Server Error") (t "Response")))

(defun write-response (stream status content-type body &optional head-p)
  (let ((octets (flexi-streams:string-to-octets body :external-format :utf-8)))
    (format stream "HTTP/1.1 ~d ~a~%" status (status-reason status))
    (format stream "Content-Type: ~a~%" content-type)
    (format stream "Content-Length: ~d~%" (length octets))
    (format stream "Connection: close~%~%")
    (unless head-p (write-sequence octets stream))
    (finish-output stream)))

(defun dispatch (method target)
  "Return (values body content-type status) for one request."
  (let* ((question (position #\? target))
         (path (if question (subseq target 0 question) target))
         (query (parse-query (when question (subseq target (1+ question)))))
         (route (find path *routes* :key #'route-path :test #'string=)))
    (cond
      ((null route)
       (values "not found" "text/plain; charset=utf-8" 404))
      ((and (not (string= method "GET")) (not (string= method "HEAD")))
       (values "method not allowed" "text/plain; charset=utf-8" 405))
      (t
       (funcall (route-handler route) query)))))

(defun handle-connection (socket)
  (let ((stream (flexi-streams:make-flexi-stream (usocket:socket-stream socket)
                                                 :external-format :utf-8)))
    (multiple-value-bind (method target headers) (read-request-head stream)
      (declare (ignore headers))
      (when method
        (multiple-value-bind (body content-type status)
            (handler-case (dispatch method target)
              (error (e)
                (values (format nil "internal error: ~a" e)
                        "text/plain; charset=utf-8" 500)))
          (write-response stream status content-type body
                          (string= method "HEAD")))))))

(defun serve-connections (server-socket)
  (loop
    (let ((client (usocket:socket-accept server-socket
                                         :element-type '(unsigned-byte 8))))
      (bt:make-thread
       (lambda ()
         (unwind-protect
              (ignore-errors (handle-connection client))
           (ignore-errors (usocket:socket-close client))))
       :name "analytics-connection"))))

;;; --- lifecycle ---

(defun start-server (&key (port *port*) (address *address*) (events-dir *events-dir*))
  "Start serving. Binds wg0 only unless an address was passed explicitly."
  (setf *events-dir* events-dir)
  (when *server* (stop-server))
  (let* ((bind (resolve-address address))
         (socket (usocket:socket-listen bind port
                                        :reuseaddress t
                                        :element-type '(unsigned-byte 8)
                                        :backlog 64)))
    (setf *server* socket)
    (bt:make-thread (lambda () (ignore-errors (serve-connections socket)))
                    :name "analytics-acceptor")
    (format t "autolith-analytics: events ~a; listening on ~a:~d~%"
            *events-dir* (or bind "all interfaces") port)
    *server*))

(defun stop-server ()
  (when *server*
    (ignore-errors (usocket:socket-close *server*))
    (setf *server* nil)))
