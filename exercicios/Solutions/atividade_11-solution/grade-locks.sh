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
function get-legit-dirs  {
  find . -mindepth 1 -maxdepth 1 -type d | grep -vE '^\./__MACOS' | grep -vE '^\./\.'
}
NDIRS=$(get-legit-dirs | wc -l)
test "$NDIRS" -lt 2 || \
  cleanup "Malformed archive! Expected exactly one directory, found $NDIRS" || exit 1
test  "$NDIRS" -eq  1 -o  "$(find . -mindepth 1 -maxdepth 1 -type f | wc -l)" -gt 0  || \
  cleanup "Empty archive!" || exit 1
if [ "$NDIRS" -eq 1 ]; then #only cd if there is a dir
  cd "$(get-legit-dirs)"
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

if ( ! grep -E -- '-[0-9]+' grade &> /dev/null ); then
   echo -e "Grade for $BASE$EXT: $(cat grade)"
fi

cleanup || true

exit 0

__TESTBENCH_MARKER__
� U��[ ��R�H6�����2�$_0����'C� ��T��Xm�`KJK2��1[�0����=�-Y�-_2C�����u9}�nt����^��T6�M�[�lVӿ1<�5����f��x��z�� ��N�B? ����?o���Q��\w��(�z�7����&��gĢ�����������o6��P�;fß��W�K�1/����J5e�}��k�����WG�V�!/.����J�ʳv{�����RS���j)~����0F1-:2�p0Pz.lJ�O�AI�,o��* ��RJ�3�z>�x���Θ�{�(�V,ס��m"R����h������/�����aP�{��raHl�!xn�u�PqY��B�X�)�
 �XJ�X�x�
�����ⵍ+��$�G;��\�yoP�:�J�Pă��??���>��O�]�؂��7��cc���{�t�+�O���ǯ:��Q&��
ϸנ� ��f"�^ھo;}qG^`����񗢑&?�L�R�t��QJI����>݂RUJy�r�#qè��<�z.l�A~��߼��ox:F��)���e}�]�	��V�O��������U����޾�b����>|��T�RQ�:O�.
�������W�X����H#)�5QyB戌o���qI�b�ǵr9f2-��_�ެm-@z� 8���-`S��r=�*s�t���tR�R�%�VQؐK<��~��jJ���V5iFjiW�J�P���
����B�V}��>��� �{�(h;���h�t���QK�ZV#���qVp���)u�ab1��� ��h/abH���IM�y8�uB\ѿd���"7�^8>y�v���1�s��ӭZ�Y��~��t(T�R�S顋��]w�IN�� p�b�G�2�3&)���W ���ކU�<7�U�쯖U��
EY\������]Ӡ���[2"wȃ7�������^ݬM���F���<,#�q�j�=�k���V�Zm[��w8pY�x:v`��ʶs��>eA�O	!X��8n@xo4�\�oU�F�c�1������;,�ݐ1�����e4��s��<���Za70��/��߇$�E���<�GkQD�g;d�#�N��s�9x��B�;����O��.'K�|Ef�X��;WxZ�v������ЛV��
gH:R��kc����7n5�+���p�]�����~ߥ�ؕ|�Z�<�h�/_�����)D�鸶��'�����hW�2�&��
�7��[$�~u��3v��3	%\��F���4tr�;1]�'-�� 3��'j�~����#�Bo�F����4~ˣMm�x�"��<M;5�Z�!�����cy�\���4�s��7�z�q8%
�l�e�6�:����4%B���A,K���|�]�
'�;^5OA-:�#�L�=ΦR9'����'���'2f����0r��M�rCq�=� ʃ`h�jO���,�)K�A�O=�EQ��Beh���,��gG�,I��B�z-V��t=�!V���v:S��k�^9�0�-)��E��|�Zzt|��>�@��Ó0x������O����E����3�Z��j�S�Q���WEV������:A��g�~�v������^���7��iv#�j���/*�i��sc<�p����T�\g��ȭo��?W�;
`���ˎ{=��*|�����L�dw�v�7C+ѣ��A{���/���1m$|B>P�'2g���fъ=�"Ψ�K-����귭Z�-�t�~/��9O9��/v�C#Mc�W��f�Q@�H�l��l2sq�F�m�1�v$O�H��+�Isx��^���'4ό��=��#�/QG��9"��h�`��> ��W��;r#��gs����v�V�;_�v�D�4M,O��˯.�!���HTUg&����g�`�LB��Iy�Sc#'��Z�
������F�~�|�'����~H�*����]��6�/���x�
���f���w2��47�	eC;���b��%`������qX��+�aR�Ӛ%�v�Ld'(�H�b��pl�!�-��
�&��/����b\,Ȫy��f맵q�Q[��Ϗ��T�-��t�%>�8�����WRƩ�dl�ˎ pPw�"")�3�!���߃_��Z��d�=���T�H��	_�^�S}�]2��C*�Ԑ:�=jn�#�i��.�4���Z8����6�Ș�bϢ�ByA�p?�4��i�������?�!��cÿ�c����֛��������O���v=H�bM|�uM���w�%3��53�a�Lͻ����xD�����n2Ėp�������59�lO���c�(^��8�a��|`��ru���bq��v8%C����v�U�A��3��O�' ?�d���jj�@N0�D3(���0�HyO�!�}���2W�.Ta'e1�!_�N�M�P�`��i�g|>3�ܳ3�)O����$ޢrl7�1B���m�F㑊��X�p�R��.N]K�OrL���Raѕ> <��+�Ԑ��YŪQ�Z�
�ߴ��!N)^4���"s�j�U��T^<�;8<kU������I{_\sğ_�0��40����V�Q���7�{=�qj��p��
HtyD6;�4a󎴉6�1u"�؆q�ӽ��$�04 3�G<�6�a��p�B,W���� �K��,*��-�k�f~K�^W��ޔUc�d���o5%����P�ˑ�˖[/�;I�=���1�D�k���X���5�IJBN��>`lB)�
nU9	U��5M��tAE���xMٔo��Ղ��F?3�4�+9SO_3�����A�>r���czSy����ע���j:�y��������d���JrYNn�|������c��nD�'�ş�����W?�O3��m}L$�B�� 8��5�9��w&��_�or��w��yfч�X�2��)���K�X�~�g<(�q{_���G��u�n�^���8�����z'�e�v,Y�UQ�eI,6�P@P@P@P@P@P@L� +\�� P  