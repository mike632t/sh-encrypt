<a id="top"></a>
## sh-encrypt - Encrypt and decrypt files 

Makes using openssl to encrypt and decrypt files a little bit easier.

Note that when decrypting the password is NOT checked..!

Requires bash.

### Usage

By default the script will encrypt every file specified on the command line 
in place with the same password.  The user will be prompted once to confirm 
that any existing files should be overwritten. 

e.g Encrypt all text files in the current folder (using the same password).

```
$ ./sh-encrypt.sh *.txt 
Password: 
Overwrite existing file(s) [y/N] ? y
$
```

If no files are specified then the script will read from stdin and write to
stdout.

e.g Display the encrypted contents of a file, without modifying the file.

```
$ cat 'data file.txt' | ./sh-encrypt.sh -p password
U2FsdGVkX18ZjAWD0K7ux7O3ji5xHlCSQyP2M6/auhBUZgWvcVv8Rv0Lnpbv5RTr
zFpDFyTAClXGOJU+c1OeJQ==
$
```

By default when decrypting a file the encrypted file is not modified unless 
the user specifically requests that the file be modified in place.

e.g Decrypt a file and display the plain text on the console.

```
$ ./sh-encrypt.sh 'data file.txt' -d 
Password: 
The quick brown fox jumped over the lazy dog
$
```

e.g Decrypt a file.

```
$ ./sh-encrypt.sh 'data file.txt' -d -i
Password: 
Overwrite existing file(s) [y/N] ? y
$
$ cat 'data file.txt'
The quick brown fox jumped over the lazy dog
$ 
```

If you like living dangerously you can just overwrite any existing files.

e.g Force the existing file to be overwritten 

```
$ ./sh-encrypt.sh 'data file.txt' -d -i -f
Password: 
$
```

However, if you got the password wrong you just scrambled your file.
