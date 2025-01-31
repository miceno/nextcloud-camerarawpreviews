# This file is licensed under the Affero General Public License version 3 or
# later. See the COPYING file.
# @author Bernhard Posselt <dev@bernhard-posselt.com>
# @copyright Bernhard Posselt 2016

# Generic Makefile for building and packaging a Nextcloud app which uses npm and
# Composer.
#
# Dependencies:
# * make
# * which
# * curl: used if phpunit and composer are not installed to fetch them from the web
# * tar: for building the archive
# * npm: for building and testing everything JS
#
# If no composer.json is in the app root directory, the Composer step
# will be skipped. The same goes for the package.json which can be located in
# the app root or the js/ directory.
#
# The npm command by launches the npm build script:
#
#    npm run build
#
# The npm test command launches the npm test script:
#
#    npm run test
#
# The idea behind this is to be completely testing and build tool agnostic. All
# build tools and additional package managers should be installed locally in
# your project, since this won't pollute people's global namespace.
#
# The following npm scripts in your package.json install and update the bower
# and npm dependencies and use gulp as build system (notice how everything is
# run from the node_modules folder):
#
#    "scripts": {
#        "test": "node node_modules/gulp-cli/bin/gulp.js karma",
#        "prebuild": "npm install && node_modules/bower/bin/bower install && node_modules/bower/bin/bower update",
#        "build": "node node_modules/gulp-cli/bin/gulp.js"
#    },

app_name=$(notdir $(CURDIR))
build_tools_directory=$(CURDIR)/build/tools
vendor_directory=$(CURDIR)/vendor
source_build_directory=$(CURDIR)/build/artifacts/source
source_package_name=$(source_build_directory)/$(app_name)
appstore_build_directory=$(CURDIR)/build/artifacts/appstore
appstore_package_name=$(appstore_build_directory)/$(app_name)
composer=$(shell which composer 2> /dev/null)

all: build

# Fetches the PHP and JS dependencies and compiles the JS. If no composer.json
# is present, the composer step is skipped, if no package.json or js/package.json
# is present, the npm step is skipped
.PHONY: build
build:
ifneq (,$(wildcard $(CURDIR)/composer.json))
	make composer
endif
ifneq (,$(wildcard $(CURDIR)/package.json))
	make npm
endif

# Installs and updates the composer dependencies. If composer is not installed
# a copy is fetched from the web
.PHONY: composer
composer:
ifeq (, $(composer))
	@echo "No composer command available, downloading a copy from the web"
	mkdir -p $(build_tools_directory)
	curl -sS https://getcomposer.org/installer | php
	mv composer.phar $(build_tools_directory)
	php $(build_tools_directory)/composer.phar install --prefer-dist
	php $(build_tools_directory)/composer.phar update --prefer-dist
else
	composer install --prefer-dist
	composer update --prefer-dist
endif

# Removes the appstore build
.PHONY: clean
clean:
	rm -rf ./build/artifacts
	rm -rf ./build/camerarawpreviews*tar.gz

# Builds the source and appstore package
.PHONY: dist
dist:
	composer install --prefer-dist
	make tests
	make appstore

# Builds the source package
.PHONY: perl
perl:
	$(build_tools_directory)/perl-build/build.sh

# Builds the source package
.PHONY: source
source:
	rm -rf $(source_build_directory)
	mkdir -p $(source_build_directory)
	tar cvzf $(source_package_name).tar.gz ../$(app_name) \
	--exclude-vcs \
	--exclude="../$(app_name)/build" \
	--exclude="../$(app_name)/js/node_modules" \
	--exclude="../$(app_name)/node_modules" \
	--exclude="../$(app_name)/*.log" \
	--exclude="../$(app_name)/js/*.log" \

# Builds the source package for the app store, ignores php and js tests
.PHONY: appstore
appstore:
	test -s $(vendor_directory)/exiftool/exiftool/exiftool.bin
	rm -rf $(appstore_build_directory)
	mkdir -p $(appstore_build_directory)
	rsync -r ../$(app_name)/ $(appstore_build_directory)/$(app_name) \
	--exclude ".git" \
	--exclude="build" \
	--exclude="tests" \
	--exclude="Makefile" \
	--exclude="*.log" \
	--exclude="phpunit*xml" \
	--exclude="composer.*" \
	--exclude="package.json" \
	--exclude=".*" \
	--exclude="sign-*.sh"
	
	docker run --rm -v $(appstore_build_directory)/$(app_name):/$(app_name) -v ~/.nextcloud/certificates:/certs nextcloud:24-apache php /usr/src/nextcloud/occ integrity:sign-app --path=/$(app_name) --privateKey="/certs/camerarawpreviews.key" --certificate="/certs/camerarawpreviews.crt"
	tar -czf build/$(app_name)_nextcloud.tar.gz -C "$(appstore_build_directory)" $(app_name)

# Builds the source package for the app store, ignores php and js tests
.PHONY: tests
tests:
	test -s $(vendor_directory)/exiftool/exiftool/exiftool.bin
	docker-compose exec --user=docker php phpunit  --do-not-cache-result --stop-on-failure -v --bootstrap apps2/camerarawpreviews/tests/bootstrap.php apps2/camerarawpreviews/tests/
