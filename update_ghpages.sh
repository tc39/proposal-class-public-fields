#!/bin/sh
set -x
set -o errexit
set -v

#node node_modules/.bin/ecmarkup \
#    spec/index.htm index.htm.tmp \
#    --css ecmarkup.css.tmp \
#    --js ecmarkup.js.tmp
npm run generate
mv index.htm index.htm.tmp
mv ecmarkup.css ecmarkup.css.tmp
mv ecmarkup.js ecmarkup.js.tmp

git checkout gh-pages
mv index.htm.tmp index.htm
mv ecmarkup.css.tmp ecmarkup.css
mv ecmarkup.js.tmp ecmarkup.js
git commit -a -m 'update gh-pages'
