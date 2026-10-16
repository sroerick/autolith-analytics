;;;; config.lisp --- runtime configuration.

(in-package #:autolith-analytics)

(defparameter *events-dir*
  (or (uiop:getenv "ANALYTICS_EVENTS_DIR") "events/")
  "Directory holding append-only <source>.jsonl event files.")

(defparameter *port*
  (let ((env (uiop:getenv "ANALYTICS_PORT")))
    (if env (parse-integer env :junk-allowed t) 8787))
  "TCP port to listen on.")

(defparameter *address* :wg0
  "Bind address: :WG0 resolves the wg0 interface, a string binds literally,
NIL binds all interfaces (explicit opt-in only; rule 4 says wg0 only).")

(defparameter *server* nil
  "The running hunchentoot acceptor, if any.")

(defun wg0-address ()
  "Return the IPv4 address of the wg0 interface, or NIL when absent."
  (ignore-errors
    (let* ((out (uiop:run-program '("ip" "-4" "-o" "addr" "show" "dev" "wg0")
                                  :output :string))
           (pos (and out (search "inet " out))))
      (when pos
        (let* ((rest (subseq out (+ pos 5)))
               (end (position #\/ rest)))
          (when end (subseq rest 0 end)))))))

(defun resolve-address (address)
  "Resolve a bind address. Rule 4: wg0 only; loopback is the dev fallback
when wg0 is absent."
  (etypecase address
    (null nil)
    (string address)
    ((eql :wg0)
     (or (wg0-address)
         (progn
           (warn "no wg0 interface found; binding loopback (dev fallback)")
           "127.0.0.1")))))
