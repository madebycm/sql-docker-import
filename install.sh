#!/bin/bash

# Check if the cmsql.sh file exists in the current directory
if [ ! -f cmsql.sh ]; then
    echo "cmsql.sh not found in the current directory. Please make sure it is present."
    exit 1
fi

# Make sure cmsql.sh is executable
chmod +x cmsql.sh

# Detect the shell and the corresponding environment file
if [ "$(uname)" = "Darwin" ]; then
    # macOS
    env_file=~/.zprofile
else
    # Other systems (assuming bash)
    env_file=~/.bashrc
fi

# Add the cmsql alias to the environment file
echo "alias cmsql=\"$(pwd)/cmsql.sh\"" >> "$env_file"

# Reload the environment file
if [ "$(uname)" = "Darwin" ]; then
    # macOS
    source ~/.zprofile
else
    # Other systems (assuming bash)
    source ~/.bashrc
fi

echo "The 'cmsql' alias has been added. You can now use the 'cmsql' command to run cmsql.sh."
