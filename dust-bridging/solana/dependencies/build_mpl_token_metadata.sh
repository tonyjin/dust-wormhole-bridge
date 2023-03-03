#!/bin/bash

ls mpl_token_metadata.so > /dev/null 2>&1
if [ $? -eq 0 ]; then
  exit 0
fi

wget -q https://github.com/metaplex-foundation/js/raw/main/programs/mpl_token_metadata.so
if [ $? -eq 0 ]; then
  exit 0
fi

echo "couldn't download prebuilt .so - fetching MPL repo and building from scratch instead"
git clone https://github.com/metaplex-foundation/metaplex-program-library.git \
  tmp-metaplex > /dev/null 2>&1

cd tmp-metaplex #metaplex build script expects to be run from the root its repo
./build.sh token-metadata
cd ..

mv tmp-metaplex/test-programs/mpl_token_metadata.so .
rm -rf tmp-metaplex

exit 0
