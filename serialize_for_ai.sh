#!/bin/bash
# A script to aggregate project files for an AI assistant

# First, print a tree of the files that will be included
echo "## Project File Structure"
git ls-files | tree --fromfile .
echo ""
echo "---"

# Second, print the content of each file with a header
echo "## File Contents"
git ls-files | while read -r file; do
  echo ""
  echo "### File: \`$file\`"
  echo '```'
  cat "$file"
  echo '```'
done
