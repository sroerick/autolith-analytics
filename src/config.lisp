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

(defun ipv4-address-p (string)
  (and (plusp (length string))
       (find #\. string)
       (every (lambda (char) (or (digit-char-p char) (char= char #\.)))
              string)))

(defun inet-address-after (output)
  "First IPv4 address following 'inet ' in ip(8)/ifconfig(8) OUTPUT, or NIL.
Handles Linux ip(8) (inet 10.0.0.2/24), BSD ifconfig(8) (inet 10.0.0.2 -->)
and old net-tools (inet addr:10.0.0.2)."
  (when output
    (let ((pos (search "inet " output)))
      (when pos
        (let* ((rest (subseq output (+ pos 5)))
               (end (position #\newline rest))
               (token (first (uiop:split-string (if end (subseq rest 0 end) rest)
                                                :separator '(#\space #\tab)))))
          (when token
            (let* ((raw (string-trim "addr:" token))
                   (slash (position #\/ raw))
                   (addr (if slash (subseq raw 0 slash) raw)))
              (when (ipv4-address-p addr) addr))))))))

(defun command-output (program &rest arguments)
  (ignore-errors (uiop:run-program (cons program arguments) :output :string)))

(defun wg0-address ()
  "Return the IPv4 address of the wg0 interface, or NIL when absent.
Portable across Linux (ip) and the BSDs (ifconfig)."
  (or (inet-address-after (command-output "ip" "-4" "-o" "addr" "show" "dev" "wg0"))
      (inet-address-after (command-output "ifconfig" "wg0"))
      (inet-address-after (command-output "/sbin/ifconfig" "wg0"))))

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
