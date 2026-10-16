;;;; pane.lisp --- the one HTML pane.

(in-package #:autolith-analytics)

(defun h (string)
  "HTML-escape a string."
  (with-output-to-string (out)
    (loop for ch across string
          do (case ch
               (#\< (write-string "&lt;" out))
               (#\> (write-string "&gt;" out))
               (#\& (write-string "&amp;" out))
               (#\" (write-string "&quot;" out))
               (t (write-char ch out))))))

(defun fmt-int (n)
  (format nil "~:d" n))

(defun fmt-wall (wall)
  (cond ((zerop wall) "0")
        ((< wall 10) (format nil "~,1fs" (coerce wall 'double-float)))
        (t (format nil "~,0fs" (coerce wall 'double-float)))))

(defparameter *pane-style*
  "body{font-family:system-ui,sans-serif;margin:2rem auto;max-width:52rem;padding:0 1rem;color:#222}
h1{font-size:1.3rem;margin-bottom:0}h2{font-size:1rem;margin-top:1.8rem}
.sub{color:#666;margin-top:.2rem}table{border-collapse:collapse;width:100%}
th,td{padding:.3rem .6rem;border-bottom:1px solid #ddd;text-align:left}
th{color:#666;font-weight:500;font-size:.85rem}
td.num,th.num{text-align:right}footer{margin-top:2rem;color:#888;font-size:.8rem}")

(defun bucket-table (title name-key rows)
  (with-output-to-string (out)
    (format out "<h2>~a</h2><table><thead><tr><th>~a</th><th class=\"num\">events</th><th class=\"num\">requests</th><th class=\"num\">tokens in</th><th class=\"num\">tokens out</th><th class=\"num\">cached</th><th class=\"num\">wall</th></tr></thead><tbody>~%"
            (h title) (h name-key))
    (dolist (row rows)
      (format out "<tr><td>~a</td><td class=\"num\">~a</td><td class=\"num\">~a</td><td class=\"num\">~a</td><td class=\"num\">~a</td><td class=\"num\">~a</td><td class=\"num\">~a</td></tr>~%"
              (h (gethash name-key row))
              (fmt-int (gethash "events" row))
              (fmt-int (gethash "requests" row))
              (fmt-int (gethash "tokens_in" row))
              (fmt-int (gethash "tokens_out" row))
              (fmt-int (gethash "cached_tokens" row))
              (fmt-wall (gethash "wall_s" row))))
    (write-string "</tbody></table>" out)))

(defun kinds-html (kinds)
  (let* ((pairs (sort (hash-pairs kinds) #'string< :key #'car))
         (parts (loop for (kind . count) in pairs
                      collect (format nil "~a <b>~a</b>" (h kind) (fmt-int count)))))
    (if parts
        (format nil "<p>kinds: ~{~a~^ &middot; ~}</p>" parts)
        "")))

(defun pane-html (&optional (snap (snapshot)))
  "Render the pane from SNAPSHOT."
  (let* ((r (rollup snap))
         (totals (gethash "totals" r))
         (malformed (snapshot-malformed snap)))
    (with-output-to-string (out)
      (format out "<!doctype html>~%<html><head><meta charset=\"utf-8\">~%<meta http-equiv=\"refresh\" content=\"30\">~%<title>autolith analytics</title>~%<style>~a</style></head><body>~%"
              *pane-style*)
      (write-string "<h1>autolith analytics</h1>" out)
      (format out "<p class=\"sub\">updated ~a &middot; ~a events~a</p>~%"
              (h (snapshot-generated snap))
              (fmt-int (gethash "events" r))
              (if (plusp malformed)
                  (format nil " &middot; ~a malformed refused" (fmt-int malformed))
                  ""))
      (format out "<p>requests <b>~a</b> &middot; tokens in <b>~a</b> &middot; tokens out <b>~a</b> &middot; cached <b>~a</b> &middot; wall <b>~a</b></p>~%"
              (fmt-int (gethash "requests" totals))
              (fmt-int (gethash "tokens_in" totals))
              (fmt-int (gethash "tokens_out" totals))
              (fmt-int (gethash "cached_tokens" totals))
              (fmt-wall (gethash "wall_s" totals)))
      (write-string (bucket-table "By day" "day" (gethash "by_day" r)) out)
      (write-string (bucket-table "By model" "model" (gethash "by_model" r)) out)
      (write-string (bucket-table "By actor" "actor" (gethash "by_actor" r)) out)
      (write-string (kinds-html (gethash "kinds" r)) out)
      (format out "<footer>files: ~{~a~^, ~} &middot; json: /api/rollup, /api/events, /api/health</footer>~%"
              (mapcar #'h (snapshot-files snap)))
      (write-string "</body></html>" out))))
