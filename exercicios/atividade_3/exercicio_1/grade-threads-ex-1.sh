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
� 	A[ �X�n�F�o>��ƒcR7���+�n�d�M%�u�"�1&G�G�N�&���>�_�gfx%GN�(�l�ҙo�9�����������V�~�%^���Z�5Y�f����[ۭ�7j�Fs���/G)[I �A<����˭��O����!c�"^���o��k��.�h�q@j�%n�xg����~����@��(ܿ����,U�]�zM�D�����v�}yq�6ڳ���E�h�7W/��mcW{��~s��m��	���H>���HE������i#��F��7`H��!8L��30���8�`�#�N� p�Jn4��TsGP�GQ�	�����q~��-� t��E�P>��S�r��0c��,��q�R���	��+IH� "�P�P�K�U)��U-o\�i~���t S��y�Pwr����jZb���G�S�i�>�"����o�����e��_{q~rڽ꿺i �2���DĽ�=:`*��e!־u9w�1H?��Y��yT?D��a���Q�\��SH96&{�+N�� ��by�p|�|(���J���X����^/���\�p���i�ȷ�1M��!�C(W�G����w��m��f�;�d�onn���!o#su0�|�P�l[� F�zc4�yF�/#��;�G�����S�\Nd��+��E
��}p�}�����  O��٭84A_��f"U���t5N.Q�*�}Դ`*|@��?N.�u����]ˊ�n�qJ��1��������IkN��(�̓�n�	�y���S�C�MT�膫W�X<�uB��Y��TLBc��m�M�sԗT�p���'�&��;���_*G�W��x�4�8\?�P��j���ȓ>���q���S�-��@���!�M1�)I����K�(��0�`��W) \�#�م-^Z�Z�:ު�ЙK��:3�5VV�o��:$��<�+��^}�U���r�[��/����v��r�K���Q��X<κ���C��A8̜��6�w~l(�xb��
�\�*�j���M������L�z%��d�T_`y�,!";���G��	��)!��>P��w�S9��X�#�DpPƂ7�Ij,2��t��Q��i��>��oq�x�ζ�ڰ<6֬�	��h��x���R|7��u5 Ԭ�ܹ���`4���p:M&&M�W����;r��CP�&C��_�f��/�	�)���c���,��4�\��M?�s�#UnJ���X�[v���O�7�{���B1�`P��*[<�k��/�;fs�WF��>OMO����^��'ر�M��nj�5�C�Y+Iu<f����jF��ăt 3�oYp#�%e8lW8j�)�S7 Xf��rD`�!qX�N�e��3�V��;��1}7�ڳ~���~u�C{��N��|� �ʯk�חO+����Y�⹔ߨ����O_����=�T���w�.v�� uk�-9 Y$(?�[�t�؁�x�?�R+���sP�o���(t���˫�${��n������d�|��4��}�f<�B��G����1G�}x5���^��-��C:P��(�����CP�7٥:�=��bݟ��/h����%�s����_vT@f�r�����Ҥ݀��p��b\�0���
na�.��{I*N+G�˳^�0�i���da*,*C���8z��S���"��{b�n�}�j#R�|L*q6)A���NR�}NǑ����E�A�f������ԋu$�7]��"���#��cM::W'ާ������X.�x�:G��XnVѳc�=y�M��{X=���*왛�?9J��ol�~�}�����w���(��'"jf���s6-�R�B�ߵ럝D �Kȼ�K���#f����E1U�%~j��K�o,�kLԲw�)���~�Ji��K��BK���'�&�����e�G�)&�ӂʥ'ח�같}=|��z��z��z��z���Wڎ�Q (  