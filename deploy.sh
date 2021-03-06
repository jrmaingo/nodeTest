#!/bin/bash

# ----------------------
# KUDU Deployment Script
# Version: 1.0.6
# ----------------------

# Helpers
# -------

exitWithMessageOnError () {
    if [ ! $? -eq 0 ]; then
        echo "An error has occurred during web site deployment."
        echo $1
        exit 1
    fi
}

# Prerequisites
# -------------

# Verify node.js installed
hash node 2>/dev/null
exitWithMessageOnError "Missing node.js executable, please install node.js, if already installed make sure it can be reached from current environment."

# Setup
# -----

SCRIPT_DIR="${BASH_SOURCE[0]%\\*}"
SCRIPT_DIR="${SCRIPT_DIR%/*}"
ARTIFACTS=$SCRIPT_DIR/../artifacts
KUDU_SYNC_CMD=${KUDU_SYNC_CMD//\"}

if [[ ! -n "$DEPLOYMENT_SOURCE" ]]; then
    DEPLOYMENT_SOURCE=$SCRIPT_DIR
fi

if [[ ! -n "$NEXT_MANIFEST_PATH" ]]; then
    NEXT_MANIFEST_PATH=$ARTIFACTS/manifest

    if [[ ! -n "$PREVIOUS_MANIFEST_PATH" ]]; then
        PREVIOUS_MANIFEST_PATH=$NEXT_MANIFEST_PATH
    fi
fi

if [[ ! -n "$DEPLOYMENT_TARGET" ]]; then
    DEPLOYMENT_TARGET=$ARTIFACTS/wwwroot
else
    KUDU_SERVICE=true
fi

if [[ ! -n "$KUDU_SYNC_CMD" ]]; then
    # Install kudu sync
    echo Installing Kudu Sync
    npm install kudusync -g --silent
    exitWithMessageOnError "npm failed"

    if [[ ! -n "$KUDU_SERVICE" ]]; then
        # In case we are running locally this is the correct location of kuduSync
        KUDU_SYNC_CMD=kuduSync
    else
        # In case we are running on kudu service this is the correct location of kuduSync
        KUDU_SYNC_CMD=$APPDATA/npm/node_modules/kuduSync/bin/kuduSync
    fi
fi

# Node Helpers
# ------------

selectNodeVersion () {
    if [[ -n "$KUDU_SELECT_NODE_VERSION_CMD" ]]; then
        SELECT_NODE_VERSION="$KUDU_SELECT_NODE_VERSION_CMD \"$DEPLOYMENT_SOURCE\" \"$DEPLOYMENT_TARGET\" \"$DEPLOYMENT_TEMP\""
        eval $SELECT_NODE_VERSION
        exitWithMessageOnError "select node version failed"

        if [[ -e "$DEPLOYMENT_TEMP/__nodeVersion.tmp" ]]; then
            NODE_EXE=`cat "$DEPLOYMENT_TEMP/__nodeVersion.tmp"`
            exitWithMessageOnError "getting node version failed"
        fi

        if [[ -e "$DEPLOYMENT_TEMP/__npmVersion.tmp" ]]; then
            NPM_JS_PATH=`cat "$DEPLOYMENT_TEMP/__npmVersion.tmp"`
            exitWithMessageOnError "getting npm version failed"
        fi

        if [[ ! -n "$NODE_EXE" ]]; then
            NODE_EXE=node
        fi

        NPM_CMD="\"$NODE_EXE\" \"$NPM_JS_PATH\""
    else
        NPM_CMD=npm
        NODE_EXE=node
    fi
}

##################################################################################################################################
# Deployment
# ----------

echo Handling node.js deployment.

# 2. Select node version
selectNodeVersion

# Temporarily change source
TMP_DEPLOYMENT_SOURCE=DEPLOYMENT_SOURCE
DEPLOYMENT_SOURCE=./yeomanTest

echo "deployment source: $DEPLOYMENT_SOURCE"
echo "deployment target: $DEPLOYMENT_TARGET"

# set to use https to fix firewall/proxy bug (does not work on azure)
echo setting git urls to https
git config url."https://".insteadOf git://

# 3. Install npm packages
if [ -e "$DEPLOYMENT_SOURCE/package.json" ]; then
    PREV_DIR=`pwd`
    cd "$DEPLOYMENT_SOURCE"
    eval $NPM_CMD install #--production #need to comment out to install grunt dependencies
    exitWithMessageOnError "npm failed"
    echo applying grunt glob package workaround
    cd ./node_modules/grunt > /dev/null
    eval $NPM_CMD install glob@^6.0.4 --save
    cd - > /dev/null
    exitWithMessageOnError "updating glob failed, see http://stackoverflow.com/questions/30199739/enotsup-using-grunt"
    cd $PREV_DIR > /dev/null
else
    echo "package.json not found"
fi

# 4. Install bower
if [ -e "$DEPLOYMENT_SOURCE/bower.json" ]; then
    cd "$DEPLOYMENT_SOURCE"
    echo starting bower actions
    eval $NPM_CMD install bower
    exitWithMessageOnError "installing bower failed"
    echo cleaning bower cache
    ./node_modules/.bin/bower cache clean
    ./node_modules/.bin/bower install
    exitWithMessageOnError "bower install failed"
    cd - > /dev/null
else
    echo "bower.json not found"
fi

# 5. Install grunt
if [ -e "$DEPLOYMENT_SOURCE/Gruntfile.js" ]; then
    cd "$DEPLOYMENT_SOURCE"
    eval $NPM_CMD install grunt-cli
    exitWithMessageOnError "installing grunt failed"
    ./node_modules/.bin/grunt --no-color build
    exitWithMessageOnError "grunt build failed"
    cd - > /dev/null
else
    echo "Gruntfile.js not found"
fi

echo next manifest content
cat $NEXT_MANIFEST_PATH
echo ==================
echo previous manifest content
cat $PREVIOUS_MANIFEST_PATH
echo ==================

# 6. KuduSync Again?
"$KUDU_SYNC_CMD" -v 500 -f "$DEPLOYMENT_SOURCE/dist" -t "$DEPLOYMENT_TARGET" -n "$NEXT_MANIFEST_PATH" -p "$PREVIOUS_MANIFEST_PATH" -i ".git;.hg;"
exitWithMessageOnError "Kudu Sync failed"

DEPLOYMENT_SOURCE=TMP_DEPLOYMENT_SOURCE

##################################################################################################################################

# Post deployment stub
if [[ -n "$POST_DEPLOYMENT_ACTION" ]]; then
    POST_DEPLOYMENT_ACTION=${POST_DEPLOYMENT_ACTION//\"}
    cd "${POST_DEPLOYMENT_ACTION_DIR%\\*}"
    "$POST_DEPLOYMENT_ACTION"
    exitWithMessageOnError "post deployment action failed"
fi

echo "Finished successfully."
