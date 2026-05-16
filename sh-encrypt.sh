#!/bin/bash
#
#  sh-encrypt.sh
#
#  Encrypts a file using openssh.
#
#  Requires bash 
#  
#
#  This  program is free software: you can redistribute it and/or modify it
#  under  the terms of the GNU General Public License as published  by  the
#  Free  Software Foundation, either version 3 of the License, or (at  your
#  option) any later version.
#
#  This  program  is distributed in the hope that it will  be  useful,  but
#  WITHOUT   ANY   WARRANTY;   without even   the   implied   warranty   of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General
#  Public License for more details.
#
#  We cannot check the device specified by the user is valid as it will not
#  exist until it is plugged in.  You will need to modify the list of valid
#  devices if your USB to serial adapter uses a different device name.
#
#
#  10 May 26         - Initial version - MT
#                    - Improved error handler - MT
#  14 May 26         - Prompt before overwriting existing files - MT
#                    - Optionally use a graphical interface - MT
#                    - Do not store output in a variable. This allows large
#                      files to be encrypted (providing there is sufficient 
#                      disk space) - MT
#                    - Display errors from both cat and openssl - MT
#  16 May 26         - Overwrite original file with random data - MT
#
#  ToDo              - Force overwriting.
#                    - Allow number of iterations to be changed.
#

CONSOLE=1  # Force console output. 

#
#  error [MESSAGE]
#
#  Prints a formatted error message.
#

error() {
   local _command=""
   _command=$(command -v zenity) >/dev/null 2>&1
   if [ -x "$_command" ] && [ $CONSOLE -eq 0 ]; then  # Use graphical message box.
      $_command --error --title="Error" --text="${1:-"Unknown Error"}\n\t\t\t\t\t\t\t\t\t\t\t\t" # Pad text.
   else
      printf "%b\n" "${0}: ${1:-Unknown Error}" >&2  # Substitutes "Unknown Error" if no error message is defined.
   fi
}

#
#  confirm [PROMPT]
#
#  Prints a prompt and waits for the user to respond. Invalid responses are
#  ignored.
#
#  Returns true if user enters Yes or selects OK and false otherwise.
#

function confirm {
   local _prompt="$@"  # Get message text.
   local _response=""
   [ -z "$_prompt" ] && _prompt="Continue"  # Default text.
   _command=$(command -v zenity) >/dev/null 2>&1
   if [ -x "$_command" ] && [ $CONSOLE -eq 0 ]; then # Use graphical message box.   
      if zenity --question --title="" --text="$_prompt"; then
         return 0  # OK pressed
      else
         return 1  # Cancel pressed or dialog closed.
      fi
   else
      while true; do
         printf '%s [y/n] ? ' "$_prompt" >/dev/tty  # Display prompt on console
         if ! read -r _response </dev/tty ; then printf '\n'; return 1; fi  # Return false on EOF (don't use timeout as it is not portable.
         case "$_response" in
            [Yy][e][s]|[Y][E][S]|[Yy])  # Yes or Y.
               return 0
               ;;
            [Nn][o]|[N][O]|[Nn])  # No or N.
               return 1
               ;;
            *)  # Anything else (including a blank) is invalid.
               ;;
         esac
      done
   fi
}

#
#  inquire [PROMPT]
#
#  Prints a message  and waits for the user to enter some text.
#

function inquire {
   local _prompt="$@"  # Get prompt.
   local _password=""
   local _command=""
   [ -z "$_prompt" ] && _prompt="Password"  # Use default prompt of not specified.

   _command=$(command -v zenity 2>/dev/null || true)
   if [ -x "$_command" ] && [ $CONSOLE -eq 0 ]; then # Use graphical message box.
      _password=$(zenity --password --title="Enter Password")
   else
      read -s -p "$_prompt: " _password < /dev/tty  # Prompt for password from terminal without echo.
      printf "\n" > /dev/tty
   fi
   printf "%s" "$_password"
}



_status=0
_count=0
_decrypt=""
_password=""
_scratch=""
_args=""

while [ $# -gt 0 ] && [ $_status -eq 0 ]; do  # Scan command line arguments.
   case "$1" in
   --help)
      printf "Usage: $0 [OPTION]... [FILE...]\n"
      printf "Encrypts FILES in place overwriting the existing file.\n\n"
      printf "  -d, --decrypt            decrypt input file/stream\n"
      printf "  -p, --password PASSWORD  specify password\n"
      printf "         --help            show this help and exit\n\n"
      printf "Reads from stdin and outputs to stdout if no files specified.\n\n"
      exit 0
      ;;
   --decrypt|-d)  # Select decryption option.
      _decrypt="-d"
      shift 1
      ;;
#   --iterations|-i)  # An example of an option with a parameter.
#      case $2 in
#      -*|"")  # Blank or another qualifier.
#         error "number of iterations not specified."
#         _status=1
#         ;;
#      *)
#         case $2 in  # Check that argument is an integer.
#         ''|*[!0-9]*) 
#            error "invalid $1 argument '$2'"
#            _status=1
#            ;;
#         *) 
#            _iterations=$2
#            ;;
#         esac
#         shift 2
#         ;;
#      esac 
#      ;;
   --password|-p)  # An example of an option with a parameter.
      case $2 in
      -*|"")  # Blank or another qualifier.
         error "password not specified."
         _status=1 ;;
      *)
         _password="$2"
         shift 2
         ;;
      esac
      ;;
   -*) # Unrecognized qualifier!
      error "unrecognized option '$1'\nTry '$0 --help' for more information."
      _status=1 
      ;;
   *) # Append each argument to args[] (preserving quoted strings).
      _args[$_count]="$1"
      _count=$((_count+1)) 
      shift
      ;;
   esac
done

set -o pipefail  #  Ensure that the status reflects any errors in a pipeline (returns first error status).

if [ -z "$_password" ]; then  # If password not specified on the command line.
   _password=$(inquire "Password")
fi

if [ -z "$_password" ]; then
   error "No password entered!"
   _status=1
   echo ""
else
   _count=0
   while [ $_count -lt ${#_args[@]} ] && [ "$_status" = 0 ]; do
      _filename="${_args[$_count]}"
      if [ -n "$_filename" ]; then
         _scratch=`mktemp` || _status=1  # Create a temporary file.
         if [ "$_status" -eq 0 ]; then

            #(cat "$_filename" 2>&1 >&3 3>&- | sed "s|^cat: |$0: |" >&2 3>&-) 3>&1 | openssl enc -aes-256-cbc -base64 -iter 7 -k "$_password" $_decrypt > "$_scratch"  # Encrypt or decrypt file and write output to temporary file.
            
            (cat "$_filename" 2>&1 >&3 3>&- | sed "s|^cat: |$0: |" >&2 3>&-) 3>&1 | \
            (openssl enc -aes-256-cbc -base64 -iter 7 -k "$_password" $_decrypt 2>&1 >&3 3>&- | sed "s|^|$0: |" >&2 3>&-) 3>&1 | cat > "$_scratch"  # Encrypt or decrypt file rewriting an error messages.
            _status=$?

            if [ $_status -eq 0 ]; then
               if confirm "Overwrite existing file"; then  # Confirm deletion of original file.
                  _blocks=$(($(ls -alis ${_filename}| cut -f 7 -d ' ')/ 512 + 1))  
                  dd if=/dev/urandom of="$_filename" conv=notrunc bs=512 count="$_blocks" >/dev/null 2>&1  # Not really secure but quicker than wipe.. 
                  mv "$_scratch" "$_filename"  # Replace the original file with the temporary copy.
                  _status=$?
                  if [ $_status -ne 0 ]; then
                     error "Unable to overwrite '$_filename'"
                  fi
               fi
            fi
            if [ -n "$_scratch" ] && [ -f "$_scratch" ]; then  # Remove temporary file if it exists.
               rm -f "$_scratch"; 
            fi
         fi
      else

         #(cat 2>&1 >&3 3>&- | sed "s|^cat: |$0: |" >&2 3>&-) 3>&1 | openssl enc -aes-256-cbc -base64 -iter 7 -k "$_password" $_decrypt  # Encrypt or decrypt input stream

         (cat 2>&1 >&3 3>&- | sed "s|^cat: |$0: |" >&2 3>&-) 3>&1 | \
         (openssl enc -aes-256-cbc -base64 -iter 7 -k "$_password" $_decrypt 2>&1 >&3 3>&- | sed "s|^|$0: |" >&2 3>&-) 3>&1 | cat
         _status=$?
         
      fi
      ((_count++))
   done
fi

exit "$_status"  # Exit with the _status code.
