#!/bin/bash

echo "digraph G {" > graph.dot
echo "rankdir=LR" >> graph.dot
echo "node [shape=box]" >> graph.dot

for file in $(find QuizFlash -name "*.swift"); do
    filename=$(basename "$file" .swift)

    grep -E "ViewModel|Service|Manager|Model" "$file" | while read line; do
        dep=$(echo $line | grep -Eo "[A-Za-z]+(ViewModel|Service|Manager|Model)")
        if [ ! -z "$dep" ]; then
            echo "\"$filename\" -> \"$dep\"" >> graph.dot
        fi
    done
done

echo "}" >> graph.dot

dot -Tsvg graph.dot -o architecture_advanced.svg

echo "Diagram generated: architecture_advanced.svg"
