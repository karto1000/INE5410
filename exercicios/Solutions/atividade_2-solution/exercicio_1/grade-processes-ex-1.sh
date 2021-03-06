#!/bin/bash
# Usage: grade dir_or_archive [output]

# Ensure realpath 
realpath . &>/dev/null
HAD_REALPATH=$(test "$?" -eq 127 && echo no || echo yes)
if [ "$HAD_REALPATH" = "no" ]; then
  cat > /tmp/realpath-grade.c <<EOF
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv) {
  char* path = argv[1];
  char result[8192];
  memset(result, 0, 8192);

  if (argc == 1) {
      printf("Usage: %s path\n", argv[0]);
      return 2;
  }
  
  if (realpath(path, result)) {
    printf("%s\n", result);
    return 0;
  } else {
    printf("%s\n", argv[1]);
    return 1;
  }
}
EOF
  cc -o /tmp/realpath-grade /tmp/realpath-grade.c
  function realpath () {
    /tmp/realpath-grade $@
  }
fi

INFILE=$1
if [ -z "$INFILE" ]; then
  CWD_KBS=$(du -d 0 . | cut -f 1)
  if [ -n "$CWD_KBS" -a "$CWD_KBS" -gt 20000 ]; then
    echo "Chamado sem argumentos."\
         "Supus que \".\" deve ser avaliado, mas esse diretório é muito grande!"\
         "Se realmente deseja avaliar \".\", execute $0 ."
    exit 1
  fi
fi
test -z "$INFILE" && INFILE="."
INFILE=$(realpath "$INFILE")
# grades.csv is optional
OUTPUT=""
test -z "$2" || OUTPUT=$(realpath "$2")
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"
# Absolute path to this script
THEPACK="${DIR}/$(basename "${BASH_SOURCE[0]}")"
STARTDIR=$(pwd)

# Split basename and extension
BASE=$(basename "$INFILE")
EXT=""
if [ ! -d "$INFILE" ]; then
  BASE=$(echo $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\1/g')
  EXT=$(echo  $(basename "$INFILE") | sed -E 's/^(.*)(\.(c|zip|(tar\.)?(gz|bz2|xz)))$/\2/g')
fi

# Setup working dir
rm -fr "/tmp/$BASE-test" || true
mkdir "/tmp/$BASE-test" || ( echo "Could not mkdir /tmp/$BASE-test"; exit 1 )
UNPACK_ROOT="/tmp/$BASE-test"
cd "$UNPACK_ROOT"

function cleanup () {
  test -n "$1" && echo "$1"
  cd "$STARTDIR"
  rm -fr "/tmp/$BASE-test"
  test "$HAD_REALPATH" = "yes" || rm /tmp/realpath-grade* &>/dev/null
  return 1 # helps with precedence
}

# Avoid messing up with the running user's home directory
# Not entirely safe, running as another user is recommended
export HOME=.

# Check if file is a tar archive
ISTAR=no
if [ ! -d "$INFILE" ]; then
  ISTAR=$( (tar tf "$INFILE" &> /dev/null && echo yes) || echo no )
fi

# Unpack the submission (or copy the dir)
if [ -d "$INFILE" ]; then
  cp -r "$INFILE" . || cleanup || exit 1 
elif [ "$EXT" = ".c" ]; then
  echo "Corrigindo um único arquivo .c. O recomendado é corrigir uma pasta ou  arquivo .tar.{gz,bz2,xz}, zip, como enviado ao moodle"
  mkdir c-files || cleanup || exit 1
  cp "$INFILE" c-files/ ||  cleanup || exit 1
elif [ "$EXT" = ".zip" ]; then
  unzip "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.gz" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.bz2" ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".tar.xz" ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "yes" ]; then
  tar zxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".gz" -a "$ISTAR" = "no" ]; then
  gzip -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "yes"  ]; then
  tar jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".bz2" -a "$ISTAR" = "no" ]; then
  bzip2 -cdk "$INFILE" > "$BASE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "yes"  ]; then
  tar Jxf "$INFILE" || cleanup || exit 1
elif [ "$EXT" = ".xz" -a "$ISTAR" = "no" ]; then
  xz -cdk "$INFILE" > "$BASE" || cleanup || exit 1
else
  echo "Unknown extension $EXT"; cleanup; exit 1
fi

# There must be exactly one top-level dir inside the submission
# As a fallback, if there is no directory, will work directly on 
# tmp/$BASE-test, but in this case there must be files! 
NDIRS=$(find . -mindepth 1 -maxdepth 1 -type d | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(find . -mindepth 1 -maxdepth 1 -type d)"
fi

# Unpack the testbench
tail -n +$(($(grep -ahn  '^__TESTBENCH_MARKER__' "$THEPACK" | cut -f1 -d:) +1)) "$THEPACK" | tar zx
cd testbench || cleanup || exit 1

# Deploy additional binaries so that validate.sh can use them
test "$HAD_REALPATH" = "yes" || cp /tmp/realpath-grade "tools/realpath"
export PATH="$PATH:$(realpath "tools")"

# Run validate
(./validate.sh 2>&1 | tee validate.log) || cleanup || exit 1

# Write output file
if [ -n "$OUTPUT" ]; then
  #write grade
  echo "@@@###grade:" > result
  cat grade >> result || cleanup || exit 1
  #write feedback, falling back to validate.log
  echo "@@@###feedback:" >> result
  (test -f feedback && cat feedback >> result) || \
    (test -f validate.log && cat validate.log >> result) || \
    cleanup "No feedback file!" || exit 1
  #Copy result to output
  test ! -d "$OUTPUT" || cleanup "$OUTPUT is a directory!" || exit 1
  rm -f "$OUTPUT"
  cp result "$OUTPUT"
fi

echo -e "Grade for $BASE$EXT: $(cat grade)"

cleanup || true

exit 0

__TESTBENCH_MARKER__
� A[ �XmS�F�~�"Tb�%CcC��2�P����Εd��K�L?�S~�{w�}~''�N�� �Z�>�����-�Nyᛑ��Y����Ys�kFn�Z��Xw�]�s+����};HC��	� H@߱�q�Y�����p��$�>��Z5��w����#�S�-a��t̊���x�k5��3?���<�K��[�oI�1��u�5'{u�b쟽9��[U�������n�����˽���V��v��}k�Ǐ0`)������h���BLK�,n���8���Ԍ��l�E<�3� ��F��>��ZPx��&� �u8�M���i 	�R�Oր�=����%,�~z���R�d�kS�J�3��g����x�B^D�BB)�Dw�d�c���\	[ށ�˥�w,W�Č0����z��J�K�6��c3���x�olT���.�׿qt�wи9{s!�@�e�b����=&��τ�Z{�★m�y�G�~��Ps�O���\L�R��xwOI����K���I�n��(�7\Nɛ��� �ʠ���C�w9��5��嘖�3Z�Г��ib{<Lh�@���e�����n�v���fc���.--Y&TD�{�n�����J|�m�"���T��M�Q(+�qz U$��q�*2�U�X̔LB��m�zek @j����f(�$���u;�*
�4��l9Z�4U��dQW �㗟�.����y^w��ȴvʹ�Ks,�u4X7F�\��F�*�\U�su��#������=MT��3�fʮ?T�� �ٙ0W:&�1�k�%�=�K�X$���d]���&��K��*��ˀ��^�¤W��J��\��YTUjZ/�4C
�D)
)-1�!���.9EAR�����r�*�0%�*�W� R+Fav��嫒���gEvF�a�����{0�$�w�c��_��o�������� }�{>�J���ez�]i-���a�d���i(��v��Q������ą�'6�������]c	�y�>�ED?��4�����-R=��3�a�`��K?}G#�y�߸r�c��2����,/�$����у�&���%>���xMׇ�Πt/��Ze�XX�)��^�c���I�>d�1�h��a�{���#��R
x�(ew��`i��������0�Q@�2�R*�jS����FM�N5)���X60G�k���'�`H�������ix$�Q�H��X���٦g��|�1�(��q̯�a�ߋ���ұ�_�>���0���v��H�s ��N`�D�.��(Ǡ�Ι�Z,�TO|>WL	��(9�@҂9���X� 0!'��|ۘ�o	��SY��vE��p��w�#;>�[� ]?�����#[��p�U�� �Ԇ�]�P��ǵO�	%�4�,~�ZY��L�0T}��h�[$E���_����[Sie��ew��R�r�ǽ)���g����܁3%n�U�R��yz�(�e�K�.)JP�$Lx��T�V ��H 2�\���(�&s�v���dz��5p�Dk�=�{
����j��a�� �����5�먖��%"c'*?�H���Ԙ���Rŝ���fD���种�r�)��r�)��r���@�dV� (  