;;;; autolith-analytics.asd --- fleet analytics: reader, rollups, JSON API, one HTML pane.

(defsystem "autolith-analytics"
  :description "Fleet analytics: tail append-only event files, roll up spend per day/model/actor, serve JSON and one HTML pane. Binds wg0 only."
  :author "roerick"
  :license "MIT"
  :version "0.1.0"
  :serial t
  :depends-on ("uiop"
               "bordeaux-threads"
               "usocket"
               "flexi-streams"
               "yason")
  :components ((:file "src/package")
               (:file "src/config")
               (:file "src/reader")
               (:file "src/rollup")
               (:file "src/pane")
               (:file "src/server")
               (:file "src/main")))
