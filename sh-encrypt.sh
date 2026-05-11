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
#   3 Jun 24         - Improved error handler - MT
#
#  ToDo              - Use a duplicate output stream.
#
#

CONSOLE=1  # Force console output


error()  # Function to display error messages 
{
   _command=$(command -v zenity) >/dev/null 2>&1
   if [ -x "$_command" ] && [ -z "$CONSOLE" ]; then # Use graphical message box.
      $_command --error --title="Error" --text="${1:-"Unknown Error"}\n\t\t\t\t\t\t\t\t\t\t\t\t" # Pad text
   else
      printf "%b\n" "${0}: ${1:-Unknown Error}" >&2  # Substitutes "Unknown Error" if no error message is defined.
   fi
}

_status=0
_count=0
_decrypt=0
_password=""
_scratch=""
_args=""

while [ $# -gt 0 ] && [ $_status -eq 0 ]; do  # Scan command line arguments
   case "$1" in
   --help)
      echo "syntax: $0 [OPTION]... FILE"
#    echo "   -o, --opt                            Describe opt here."
      echo "         --help                           display this help and exit"
      exit 0
      ;;
   --decrypt|-d)  # Decrypt.
      _decrypt=1
      shift 1
      ;;
   --iterations|-i)  # An example of an option with a parameter
      case $2 in
      -*|"")  # Blank or another qualifier
         error "number of iterations not specified."
         _status=1
         ;;
      *)
         case $2 in  # Check that argument is an integer
         ''|*[!0-9]*) 
            error "invalid $1 argument '$2'"
            _status=1
            ;;
         *) 
            _iterations=$2
            ;;
         esac
         shift 2
         ;;
      esac 
      ;;
   --password|-p)  # An example of an option with a parameter
      case $2 in
      -*|"")  # Blank or another qualifier
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


#for i in ${!_args[@]}; do
#   echo "** $(($i+1)) '${_args[$i]}'"
#done

if [ -z "$_password" ]; then  # If password not specified on the command line.
   _command=$(command -v zenity 2>/dev/null || true)
   if [ -x "$_command" ] && [ $CONSOLE -eq 0 ]; then # Use graphical message box.
      _password=$(zenity --password --title="Enter Password")
   else
      read -s -p "Password: " _password < /dev/tty  # Prompt for password from terminal without echo
      printf "\n"
   fi
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
         _output="$(cat "$_filename" 2>&1)"  # Capture all output.
         _status=$?
         if [ "$_status" -ne 0 ]; then
            _output="${_output#cat: }"  # Remove "cat: "
            error "$_output"  # Print error
         else
            _scratch=`mktemp` || _status=1  # Create a temporary file.
            if [ "$_status" -eq 0 ]; then
               if [ $_decrypt -eq 1 ]; then
                  _output=$(echo "$_output" | openssl enc -aes-256-cbc -base64 -iter 7 -k "$_password" -d > "$_scratch")  # Decrypt file and write output to temporary file.
                  _status=$?
               else
                  _output=$(echo "$_output" | openssl enc -aes-256-cbc -base64 -iter 7 -k "$_password" > "$_scratch")  # Encrypt file and write output to temporary file.
                  _status=$?
               fi
               if [ $_status -ne 0 ]; then
                  error "Encryption failed!"
               else
                  mv "$_scratch" "$_filename"  # Replace the original file with the temporary copy
                  _status=$?
                  if [ $_status -ne 0 ]; then
                     error "Unable to overwrite '$_filename'"
                  fi
               fi
               if [ -n "$_scratch" ] && [ -f "$_scratch" ]; then  # Remove temporary file if it exists
                  rm -f "$_scratch"; 
               fi
            fi
         fi
      else
         _output="$(cat 2>&1)"  # Capture all output.
         _status=$?
         if [ "$_status" -ne 0 ]; then  # Unlikely cat will throw an error here but check anyway.
            _output="${_output#cat: }"  # Remove "cat: "
            error "$_output"  # Print error.
         else
            #echo "$_output"
            if [ $_decrypt -eq 1 ]; then
               _output=$(echo "$_output" | openssl enc -aes-256-cbc -base64 -iter 7 -k "$_password" -d)  # Decrypt file.
               _status=$?
            else
               _output=$(echo "$_output" | openssl enc -aes-256-cbc -base64 -iter 7 -k "$_password")  # Encrypt file.
               _status=$?
            fi
            if [ $_status -ne 0 ]; then
               error "Encryption failed!"
            else
               printf "%s\n" "$_output"
            fi
         fi
      fi
      ((_count++))
   done
fi

exit "$_status"  # Exit with the _status code
