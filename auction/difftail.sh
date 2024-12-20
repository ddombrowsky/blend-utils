#!/bin/sh

if [ -e tail.sh.new ] ; then
    mv tail.sh.new tail.sh.old
fi

./tail.sh | tee tail.sh.new

echo
echo === DIFF ===
diff -u tail.sh.old tail.sh.new | tee .ddd

if [ -s .ddd ] ; then
    mv .ddd tail.sh.lastdiff
fi
