;;;; build.lisp --- build bin/autolith-analytics (run from the repository root).

(require :asdf)
(let ((setup (merge-pathnames "quicklisp/setup.lisp" (user-homedir-pathname))))
  (when (probe-file setup)
    (load setup)))
(asdf:load-system :autolith-analytics)
(aana:dump-executable)
