;;;; package.lisp --- package definition for autolith-analytics.

(defpackage #:autolith-analytics
  (:documentation "Fleet analytics: tail append-only event files, roll up spend per day/model/actor, serve JSON and one HTML pane.")
  (:use #:cl)
  (:nicknames #:aana)
  (:export
   ;; entry points
   #:main
   #:self-test
   #:start-server
   #:stop-server
   #:dump-executable
   ;; config
   #:*events-dir*
   #:*port*
   #:*address*
   #:wg0-address
   ;; data
   #:snapshot
   #:load-snapshot
   #:rollup
   #:snapshot-events
   #:snapshot-malformed
   #:snapshot-files
   #:snapshot-generated
   #:parse-event
   #:display-kind))
