#!/bin/bash
#
#  sh-encrypt.sh
#
#  Encrypts a file using openssh.
#
#  Requires bash + sed + grep 
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
#  10 May 26   0.1   - Initial version - MT
#                    - Improved error handler - MT
#  14 May 26         - Prompt before overwriting existing files - MT
#                    - Optionally use a graphical interface - MT
#                    - Do not store output in a variable. This allows large
#                      files to be encrypted (providing there is sufficient 
#                      disk space) - MT
#                    - Display errors from both cat and openssl - MT
#  16 May 26         - Overwrite original file with random data - MT
#                    - Improved error handling - MT
#                    - Do not overwrite unless scratch file exists - MT
#                    - Only print first line of an error message - MT
#                    - Added support for legacy systems - MT
#  17 May 26         - Checks openssl version and automatically uses legacy 
#                      options if required - MT
#                    - Fixed use of dd on legacy systems - MT
#                    - Check for command line errors before continuing - MT
#                    - Added option to display the version - MT
#                    - Made check_version() POSIX compliant for portability
#                      to other systems - MT
#  18 May 26   0.2   - Changed the default behaviour when decrypting a file 
#                      to write the plaintext to the console - MT
#                    - Added an option to allow the user to modify files in 
#                      place - MT
#             (0019) - User can force files to be overwritten without being
#                      prompted to confirm - MT
#                    - File size and temporary filename generation modified
#                      to make them more portable - MT
#  24 May 26         - Added hint to 'Bad decrypt' error message - MT
#  25 May 26         - Replaced while loop an counter with a for loop - MT
#                    - Updated command line parser to allow multiple single
#                      letter options to be combined - MT
#              0.3   - Doesn't use bash arrays to hold arguments to improve 
#                      compatibility with legacy systems - MT
#  29 May 26         - Only display the first line of an error message - MT
#
#  ToDo              - 
#                    
#

VERSION=0.3.0024
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

confirm() {
   local _prompt="$@"  # Get message text.
   local _response=""
   
   if [ -z "$_prompt" ]; then _prompt="Continue"; fi  # Default text.
   _command=$(command -v zenity) >/dev/null 2>&1
   if [ -x "$_command" ] && [ $CONSOLE -eq 0 ]; then # Use graphical message box.   
      if zenity --question --title="" --text="$_prompt"; then
         return 0  # OK pressed
      else
         return 1  # Cancel pressed or dialog closed.
      fi
   else
      while true; do
         printf '%s [y/N] ? ' "$_prompt" >/dev/tty  # Display prompt on console
         if ! read -r _response </dev/tty ; then printf '\n'; return 1; fi  # Return false on EOF (don't use timeout as it is not portable.
         case "$_response" in
            [Yy][e][s]|[Y][E][S]|[Yy])  # Yes or Y.
               return 0
               ;;
            [Nn][o]|[N][O]|[Nn]|"")  # No, N or blank  (Default to N)
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

inquire() {
   local _prompt="$@"  # Get prompt.
   local _password=""
   local _command=""
   
   if [ -z "$_prompt" ]; then _prompt="Password"; fi # Use default prompt of not specified.
   _command=$(command -v zenity 2>/dev/null || true)
   if [ -x "$_command" ] && [ $CONSOLE -eq 0 ]; then # Use graphical message box.
      _password=$(zenity --password --title="Enter Password")
   else
      read -s -p "$_prompt: " _password < /dev/tty  # Prompt for password from terminal without echo.
      printf "\n" > /dev/tty
   fi
   printf "%s" "$_password"
}

#
#  compare REQUIRED CURRENT
#
#  POSIX compliant.
#
#  Splits up version numbers and compares them.  
#
#  Returns true if current version is greater then or equal to the required 
#  version.
#

compare() {
   _required=`printf "%s" "$1" | tr . ' '`  # Convert dots to spaces (so we can iterate over each number).
   _version=`printf "%s" "$2" | tr . ' '`
   set -- $_required  # Convert required version into positional parameters.
   for _value in $_version; do  # Loop over each value in the version number .
      _min=$1
      if [ -z "$_min" ]; then _min=0; fi  # Replace any missing value with zeros.
      if [ "$_value" -gt "$_min" ]; then  # If version is newer than required version return true.
         return 0
      elif [ "$_value" -lt "$_min" ]; then  # If version is older than required version return false.
         return 1
      fi
      shift  #  Everything the same so far check next values.
   done

   for _min in "$@"; do
      if [ "$_min" -gt 0 ]; then  # If any additional minor versions are greater then zero return false.
         return 1
      fi
   done
   return 0
}


help() {
   printf "Usage: $0 [OPTION]... [FILE...]\n"
   printf "Encrypts FILES in place overwriting the existing file.\n\n"
   printf "  -d, --decrypt            decrypt input file/stream\n"
   printf "  -f, --force              overwrite without prompting\n"
   printf "  -i, --inplace            modify file in place\n"
   printf "  -l, --legacy             use legacy encryption settings\n"
   printf "  -p, --password PASSWORD  specify password\n"
   printf "      --legacy             use backward compatible settings\n"
   printf "      --help               show this help and exit\n\n"
   printf "      --version            show version and exit\n\n"
   printf "Reads from stdin if no files specified and outputs to stdout.\n\n"
}

about() {
   printf "%s: Version %s\n" $0 $VERSION
   printf "Copyright(C) 2026 MT\n"
   printf "License GPLv3+: GNU GPL version 3 or later <http://gnu.org/licenses/gpl.html>.\n"
   printf "This is free software: you are free to change and redistribute it.\n"
   printf "There is NO WARRANTY, to the extent permitted by law.\n"
}

password() {
   case $2 in
   -*|"")  # Blank or another qualifier.
      error "password not specified."
      _status=1
      ;;
   *)
      _password="$2"
      ;;
   esac
}
      
_status=0
_count=0
_overwrite=0
_force=0
_options="-aes-256-cbc -pbkdf2 -iter 200000 -md sha512 -salt -base64 "  # Default options for modern openssl implementations.
_legacy="-aes-256-cbc -salt -md sha1 -base64 "  # Options for legacy systems.
_mode="-e"  # Encrypt by default.
_password=""
_scratch=""
_args=""
_token=`printf '\377'`  # Use DEL to encode spaces in arguments. 

while [ $# -gt 0 ] && [ $_status -eq 0 ]; do  # Parse command line arguments.
   case "$1" in
   --help)
      help
      _status=1
      ;;
   --decrypt)  # Select decryption option.
      _mode="-d"
      shift
      ;;
   --force)  # Select decryption option.
      _force=1
      shift
      ;;
   --inplace)  # Overwrite existing file 
      _overwrite=1
      shift
      ;;
   --legacy)  # Use backward compatible settings.
      _options="$_legacy"
      shift
      ;;
   --version)  # Show version information.
      about
      _status=1
      ;;
   --password)  # An option with a parameter.
      password $1 $2
      shift 2
      ;;
   --*) # Unrecognized qualifier!
      error "unrecognized option '$1'\nTry '$0 --help' for more information."
      _status=1 
      ;;
   -*)
      _option=`printf '%s\n' "$1" | sed 's/^-//'`  # Don't confuse with options.
      while [ -n "$_option" ] && [ $_status -eq 0 ]; do
         _next=`printf '%s\n' "$_option" | sed 's/^\(.\).*$/\1/'`
         _option=`printf '%s\n' "$_option" | sed 's/^.\(.*\)$/\1/'`
         case "$_next" in
         d) _mode="-d"  # Decrypt
            ;;
         f) _force=1  # Do not prompt to overwrite (very dangerous particularly when decrypting as the encrypted file will be overwritten with gibberish if the password is wrong) 
            ;;
         i) _overwrite=1  # Overwrite existing file. 
            ;;
         l) _options="$_legacy"  # Use backward compatible settings.
            ;;
         p) if [ -n "$_option" ]; then  # Allows password specified in the option (e.g '-ppassword').
               password "$1" "$_option"
               _option=""
            else
               password "$1" "$2"
               shift
            fi
            ;;
         *) error "invalid option -- '$_next'\nTry '$0 --help' for more information."
            _status=1 
            ;;
         esac
      done
      shift
      ;;
   *) # Append each argument (preserving quoted strings).
#      _args[$_count]="$1"
#      _count=$((_count+1)) 

      if [ -z "$_args" ]; then
         _args="$1"
      else
         # Note - Newline is part of string.
         _args="$_args
$1"
      fi

      shift
      ;;
   esac
done

if [ $_status -eq 0 ]; then  # Check there were no errors on the command line.
   _version=$(openssl version | sed -n 's/[^0-9]*\([0-9]\{1,\}\(\.[0-9]\{1,\}\)\{1,\}\).*/\1/p')  # Get openssl version number.
   if ! compare 1.1.0 $_version; then  # Check openssl version meets requirements.
      _options="$_legacy"  # Use legacy options if it doesn't.
   fi

   set -o pipefail  #  Ensure that the status reflects any errors in a pipeline (returns first error status).
   
   if [ -n "$TMPDIR" ]; then _tmp="$TMPDIR"; else _tmp="/tmp"; fi

   if [ -z "$_password" ]; then  # If password not specified on the command line.
      _password=$(inquire "Password")
   fi
   
   if [ "$_mode" = "-e" ]; then  # Encryption implies overwrite 
      _overwrite=1
   fi

   if [ -z "$_password" ]; then
      error "No password entered!"
      _status=1
      printf "\n"
   else
      #for _filename in "${_args[@]}"; do
      # Note - Do not indent here document.
      exec 3<<EOF
$_args
EOF
      while IFS= read -r _filename <&3; do # Read arguments from file descriptor
         if [ "$_status" = 0 ]; then
            if [ -n "$_filename" ]; then
               if [ $_overwrite -eq 1 ]; then
                  #_scratch=`mktemp` || _status=1  # Create a temporary file.
                  _scratch=$(mktemp "$_tmp/tmpfile.XXXXXX")  # Create a temporary file.
                  if [ "$_status" -eq 0 ]; then
                     (cat "$_filename" 2>&1 >&3 3>&- | sed "1s|^cat: |$0: |" >&2 3>&-) 3>&1 | \
                     (openssl enc $_options -k "$_password" $_mode 2>&1 >&3 3>&- | sed "1s|^|$0: |" | sed -n 1p | sed "s|error reading input file|& (is it plain text)|" | sed "s|bad decrypt|& (try legacy options)|" >&2 3>&-) 3>&1 | cat > "$_scratch"  # Encrypt or decrypt file rewriting an error messages.
                     _status=$?
                     if [ $_status -eq 0 ]; then
                        if [ $_force -eq 1 ] || confirm "Overwrite existing file(s)"; then  # Confirm deletion of original file.
                           _force=1  # Don't prompt again. 
                           if [ -e $_scratch ]; then  # Check scratch file exists (don't overwrite the original if there is nothing to replace it!).
                              #_blocks=$(($(ls -alis "$_filename" | cut -f 7 -d ' ')/ 512 + 1))  
                              _filesize=`( wc -c < "$_filename" )`  # Simpler and more portable 
                              _blocks=$(( (_filesize + 511) / 512 ))  # Arithmetic expression
                              (dd if=/dev/urandom of="$_filename" conv=notrunc bs=512 count="$_blocks" 2>&1) | grep "dd:" || true | sed "s|^dd: ||"  # Ignore error from grep if nothing matched.
                              _status=$?
                              if [ $_status -eq 0 ]; then
                                 mv "$_scratch" "$_filename" 2>&1 >/dev/null | sed "1s|^mv: |$0: |"  # Replace the original file with the temporary copy.
                                 _status=$?
                              fi
                           else
                              _status=1
                              error "cannot stat '$_scratch': No such file or directory"
                           fi
                        fi
                     fi
                     if [ -n "$_scratch" ] && [ -f "$_scratch" ]; then  # Remove temporary file if it exists.
                        rm -f "$_scratch" 2>&1 >/dev/null | sed "1s|^rm: |$0: |" 
                     fi
                  fi
               else
                  (cat "$_filename" 2>&1 >&3 3>&- | sed "1s|^cat: |$0: |" >&2 3>&-) 3>&1 | \
                  (openssl enc $_options -k "$_password" $_mode 2>&1 >&3 3>&- | sed "1s|^|$0: |" | sed -n 1p | sed "s|error reading input file|& (is it plain text)|" | sed "s|bad decrypt|& (try legacy options)|" >&2 3>&-) 3>&1 | cat  # Encrypt or decrypt file rewriting an error messages.
                  _status=$?
               fi
            else
               (cat 2>&1 >&3 3>&- | sed "1s|^cat: |$0: |" >&2 3>&-) 3>&1 | \
               (openssl enc $_options -k "$_password" $_mode 2>&1 >&3 3>&- | sed "1s|^|\n$0: |" | sed -n 1p | sed "s|error reading input file|& (is it plain text)|" >&2 3>&-) 3>&1 | cat  # Encrypt or decrypt stream rewriting an error messages.
               _status=$?
            fi
         fi
      done
      exec 3>&-  # Close file descriptor. 
   fi
fi

exit "$_status"  # Exit with the _status code.
