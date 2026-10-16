;;;; main.lisp --- entry points: CLI, self-test, image dump.

(in-package #:autolith-analytics)

(defun make-test-dir ()
  (ensure-directories-exist
   (uiop:merge-pathnames*
    (format nil "autolith-analytics-selftest-~36r/"
            (random (expt 36 8) (make-random-state t)))
    (uiop:default-temporary-directory))))

(defun write-test-file (dir name lines)
  (with-open-file (out (merge-pathnames name dir)
                       :direction :output :if-exists :supersede)
    (dolist (line lines) (write-line line out))))

(defun oversized-ref ()
  (format nil "{\"ts\":\"2026-10-16T18:31:00Z\",\"schema_v\":1,\"source\":\"bridge\",\"kind\":\"message\",\"actor\":\"roerick\",\"dir\":\"out\",\"ref\":\"~a\"}"
          (make-string 250 :initial-element #\x)))

(defun self-test ()
  "Exercise the reader, hygiene, and rollups against the schema examples."
  (let* ((dir (make-test-dir))
         (ok t))
    (flet ((check (what condition)
             (format t "~a ~a~%" (if condition "ok  " "FAIL") what)
             (unless condition (setf ok nil))))
      ;; Schema examples from docs/schema-v1.md, plus an unknown kind, a
      ;; malformed line, a hygiene refusal, and the rotated file pattern.
      (write-test-file dir "autolith.jsonl"
                       (list "{\"ts\":\"2026-10-16T18:27:00Z\",\"schema_v\":1,\"source\":\"autolith\",\"kind\":\"llm-usage\",\"actor\":\"gregor\",\"model\":\"gpt-5\",\"tokens_in\":41233,\"tokens_out\":812,\"cached_tokens\":36000,\"requests\":1,\"wall_s\":6.4,\"ref\":\"job:exec:42\"}"
                             "{\"ts\":\"2026-10-16T18:28:00Z\",\"schema_v\":1,\"source\":\"autolith\",\"kind\":\"card-move\",\"actor\":\"gregor\",\"ref\":\"card:f7c4579b\"}"
                             "not json at all"))
      (write-test-file dir "pp-flow-20261016.jsonl"
                       (list "{\"ts\":\"2026-10-16T18:29:12Z\",\"schema_v\":1,\"source\":\"pp-flow\",\"kind\":\"run-step\",\"actor\":\"hollis\",\"run_id\":\"pp-pass-2026-10-16\",\"requests\":3,\"tokens_in\":1750000,\"tokens_out\":21000,\"cached_tokens\":1550000,\"wall_s\":120.5}"))
      (write-test-file dir "bridge.jsonl"
                       (list "{\"ts\":\"2026-10-16T18:30:00Z\",\"schema_v\":1,\"source\":\"bridge\",\"kind\":\"message\",\"actor\":\"roerick\",\"dir\":\"in\"}"
                             (oversized-ref)))
      (unwind-protect
           (let* ((snap (load-snapshot dir))
                  (r (rollup snap))
                  (totals (gethash "totals" r)))
             (check "4 valid events read" (= 4 (length (snapshot-events snap))))
             (check "2 malformed lines refused" (= 2 (snapshot-malformed snap)))
             (check "rotation suffix stripped"
                    (member "pp-flow" (snapshot-files snap) :test #'string=))
             (check "totals requests = 4" (= 4 (gethash "requests" totals)))
             (check "totals tokens_in = 1791233"
                    (= 1791233 (gethash "tokens_in" totals)))
             (check "totals cached_tokens = 1586000"
                    (= 1586000 (gethash "cached_tokens" totals)))
             (check "totals wall_s = 126.9"
                      (= 126.9d0 (gethash "wall_s" totals)))
             (check "by day has 2026-10-16"
                    (some (lambda (row) (string= (gethash "day" row) "2026-10-16"))
                          (gethash "by_day" r)))
             (check "unknown kind displayed as other"
                    (= 1 (gethash "other" (gethash "kinds" r))))
             (check "by model counts gpt-5"
                    (some (lambda (row) (string= (gethash "model" row) "gpt-5"))
                          (gethash "by_model" r)))
             (check "by actor counts hollis"
                    (some (lambda (row) (string= (gethash "actor" row) "hollis"))
                          (gethash "by_actor" r))))
             (check "ip(8) address parsed"
                    (string= (inet-address-after
                              "2: wg0    inet 10.8.0.2/24 scope global wg0")
                             "10.8.0.2"))
             (check "openbsd ifconfig address parsed"
                    (string= (inet-address-after
                              "wg0: flags=8051<UP> mtu 1420
	 inet 10.8.0.2 --> 10.8.0.1 prefix 32")
                             "10.8.0.2"))
             (check "inet6 not mistaken for inet"
                    (null (inet-address-after "wg0: inet6 fe80::1 prefix 64")))
        (uiop:delete-directory-tree dir :validate t :if-does-not-exist :ignore)))
    ok))

(defun parse-args (args)
  "Apply --port, --events, --address; return :check when --check was given."
  (let ((check nil))
    (loop while args
          do (let ((arg (pop args)))
               (cond
                 ((string= arg "--port")
                  (setf *port* (parse-integer (pop args))))
                 ((string= arg "--events")
                  (setf *events-dir* (pop args)))
                 ((string= arg "--address")
                  (let ((value (pop args)))
                    (setf *address*
                          (cond ((string-equal value "wg0") :wg0)
                                ((string-equal value "all") nil)
                                (t value)))))
                 ((member arg '("--check" "--self-test") :test #'string=)
                  (setf check t))
                 (t
                  (format *error-output* "unknown argument: ~a~%" arg)
                  (uiop:quit 2)))))
    check))

(defun main (&optional (args (uiop:command-line-arguments)))
  (let ((check (parse-args args)))
    (cond
      (check (uiop:quit (if (self-test) 0 1)))
        (t (handler-case (start-server)
             (error (e)
               (format *error-output* "autolith-analytics: cannot start: ~a~%" e)
               (uiop:quit 1)))
           (loop (sleep 60))))))

(defun dump-executable ()
  "Dump bin/autolith-analytics as a standalone executable image."
  (ensure-directories-exist "bin/")
  (sb-ext:save-lisp-and-die "bin/autolith-analytics"
                            :executable t
                            :toplevel (lambda ()
                                        (main (uiop:command-line-arguments)))))
