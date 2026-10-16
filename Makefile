SBCL ?= sbcl
SYSTEM := autolith-analytics

.PHONY: all build run smoke package install-links clean

all: build

build:
	./bin/build.sh

run: build
	./bin/autolith-analytics

smoke:
	$(SBCL) --noinform --non-interactive \
	  --eval "(require :asdf)" \
	  --eval "(let ((setup (merge-pathnames \"quicklisp/setup.lisp\" (user-homedir-pathname)))) (when (probe-file setup) (load setup)))" \
	  --eval "(asdf:load-system :$(SYSTEM))" \
	  --eval "(unless (autolith-analytics:self-test) (uiop:quit 1))"

package: build
	@version=$$(git describe --tags --always 2>/dev/null || echo dev); \
	mkdir -p dist; \
	tar -czf dist/autolith-analytics-$$version.tar.gz \
	  -C .. \
	  --exclude=autolith-analytics/.git \
	  --exclude=autolith-analytics/bin/autolith-analytics \
	  --exclude=autolith-analytics/dist \
	  --exclude='*.fasl' --exclude='*.lx64fsl' --exclude='*.core' \
	  autolith-analytics; \
	echo "packaged dist/autolith-analytics-$$version.tar.gz"

install-links:
	mkdir -p $(HOME)/quicklisp/local-projects
	ln -sfn $(CURDIR) $(HOME)/quicklisp/local-projects/autolith-analytics

clean:
	rm -f bin/autolith-analytics
	rm -rf dist
