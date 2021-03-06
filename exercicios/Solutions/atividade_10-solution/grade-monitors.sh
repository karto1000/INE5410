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

echo -e "Grade for $BASE$EXT: $(cat grade)"

cleanup || true

exit 0

__TESTBENCH_MARKER__
� �`�[ ��R�H2����� ɟ��c�,�$���P؜l�mY���!��w����"/v=3�-�26w��ժ�£�����M+ ~�"n�g<�7�#�T*췰S�'cxT(��K��|��x�bi��*���B?0=�G�C�m>ޢ��SF�P���bw��R��������w=�"�'�V�Ƣ��ٙ��J�Pz�ձ0�����f�l�h�~O:9:�)�~�<�)E�y���fM)������5�,����<���T$f>�� +q�_��Ű��pCǑ:�l�'A�4sU���;�@�+�����Q`t[1�$��D�;��AD�A��H��{�����5$v��0���g���i��a@�6�u]�i��r�c�gX^�4 g`)�c֛��5�*��f&U��l���"�=ރ��9�k;��ɖ:6��;�R�����Kj}�u��
[�����{�����@���������7Mb+�E�y�;��D��p9�k�l߷�.p;��A��9D���%h$��'�!�j����(%���2���f�삒\���p���:�{�<:�^`S�{�>r�q.�;F��I��m�i]hm��@��D{Vy���qMQ�F���`#��ﯯ�+�]E(2�o#3Z
�Y���#�Ţm!�4ơ7��#�G��s���_�%�v�EUc�'�\.^d��w�^n�.b@� c����3r�`ј�ӵ+�h�'��$�,B܍$y}��Ho;h�
R��䴖'#Yٗ����Q�P�0|r��5�U��*%��@.M ��0VPw�OPI3�#+���#����+��ތ�\11�kmN���/�bfHc.?���9�dB\��D�@�2?��|C����ݠ�Oz�s!o_�F�	/��_�5]�WdT:��Ă�B����	�.dt�Sx���	
��rfZ>���z>oݍ�{�B�Gƿ������!^����\�,�o��s���G���)�����̆xH�Î�����F�B��)��2P��];�|�xAuv���x3�k�t]�,ꯩˎ��$���x������yc~��s�8�g״QA-���4������< �&N�-1ێ��0v���|��C�SD�c���)$��ѫ:��LiI����Bˡ�+_ݏ��>]�l�Q�(^z���}����m2���/#LA*^H�b��D~�tL�7�n�籼����Sԧ�f�OtJ�~c�,����5���$��� �L�����<c8�B2�s3z�I���uFuJ@�������Q�D�0�}p�3�����,|��;�At [ct�M�I�y�j�oh�ܝ̀��Sn�{@�h�G.�tO�m�ujuZ��d��.�sJ/�.����8o���J�b97�6�v�T��]�z�¥o�Ӝ�1-k���J!��ɹ|g`���U���
����3�W�;v��ӆ��II�	�-q�g�g���mc&�!ҿ�S�d�K�P�V��-h�!��|!R)�tf3�G�E�� �2�HSdo��´�[0�|�+�ϑ`"���v�!u��OkKX�	�S�bBTGLNE��pϙ��RO 71o����J1VU���\c#A��M��Ɍ�2:�ǐ�at`z&����w�D��2�b+��8��;��p��A�yi�_��g5�߉�Y�E��v�;�S�m:+d)����K���5����Q�[��J?0�ͪk���4��6e>}�
<_��Khp�rb���)������V�0\Un�QI���B���֜��8O�ㆁ�5�od���-9��iu'��-&W�{8A3k<��-娋�V�-떍zˊ�Vc�i��{vn��������w�o�2��0����m���~o�k,��������r�T����߶�.�06�M^ �k��`OF�3�U���J5�NV��F%*vK�p��1�W���F$,���n\-eM��x��tQ	���z���W�d�g�L��&���rD_ԡ֢J�辄�eu�u|����4Y�
�$�<�%��;1��#�z���j$c��6���>��J���"�	�����[��vU�
чqa�8���fJQ��Z�ŔaX[�[�=���<!x���.<�E����1�J^/B�����@��tT�l�Ϛg�
�ꧧ������������G''�C�f�篎k�]~葎��#���7ظ�v㟸��;�����1ZPDv��=�M�)u����9L�}h�H���`��j�t�����t���P��iQ�� ����}g���j����t��d�]^��2'뛊qQ0�	&�a�+jz:.D����N`���-G"ޘi"��=k	�ݦ��0�@H�
瓻�h��D�B�
Ӫ�r��������Ʃhb���b���ԳK݉z�(ؤT��RӞ�0k�ƝN��$Ѻ���|��Q�r!��h�>ݨ7^lH�k�8Cޡ!�h���k��Q��!�+4���|��јiLI�?�C��۷o�6X��	UG"���k��+�*�U��@d�Ad�Ad�Ad�Ad�Ad�Ad�Ad�?���A P  