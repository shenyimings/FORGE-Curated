#!/bin/bash

# This script publishes the package to npm
# 1. runs the prepublish script to generate minimal package.json and hardhat.config.js
# 2. publishes the package
# 3. cleans up the files, restoring the original package.json and hardhat.config.ts
# 4. if published, commits and tags the release

# prepublish
# must run with hardhat to generate hardhat.config.js
yarn hardhat run scripts/prepublish.ts

if [ $? -ne 0 ]; then
    echo "Prepublish failed"
    exit 1
fi

# publish
yarn publish --non-interactive
published=$?

# clean up files
yarn hardhat clean
mv hardhat.config.ts.bak hardhat.config.ts
mv package.json.bak package.json
rm hardhat.config.js

# if published, commit and tag
if [ $published -eq 0 ]; then
    version=v$(node -p "require('./package.json').version")
    git add package.json
    git commit -m "Publish $version"
    git tag $version
fi