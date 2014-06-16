TESTS = test/*.test.coffee
REPORTER = spec
NAME    := $(shell node -e "console.log(JSON.parse(require(\
  'fs').readFileSync('package.json', 'utf8')).name)")
VERSION := $(shell node -e "console.log(JSON.parse(require(\
  'fs').readFileSync('package.json', 'utf8')).version)")
TARBALL := $(NAME)-$(VERSION).tgz

build:
	@rm -rf lib
	@coffee -c$(opt) -o lib src
	@cp src/*.html lib
	@mkdir lib/ace
	@cp src/ace/* lib/ace

watch:
	@coffee -wc$(opt) -o lib src
	@cp src/*.html lib

publish:
	@rm -Rf package
	@mkdir package
	@cp -R lib package/lib
	@cp package.json package
	@cp README.md package
	@cp LICENSE package
	@tar czf $(TARBALL) package
	@rm -r package

.PHONY: build
