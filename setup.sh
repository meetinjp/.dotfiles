#!/usr/bin/env bash

if ! command -v git &>/dev/null; then
	echo "Git is not installed. Please install it first"
	exit 1
fi

echo "Setting up Git configuration..."

read -rp "Name: " name
read -rp "Email: " email

git config --global user.name "$name"
git config --global user.email "$email"

echo "Git configuration set up successfully!"
