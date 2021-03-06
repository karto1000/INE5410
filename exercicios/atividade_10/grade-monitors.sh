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
� I��[ ��R�H�g}�Ah�L���ab�5S�l�
LVXm[AV;�2	���}�����؞�lٖ��R[�)
�ԧϭϥ�����9�[]c���DX�Vٯ�^5��),X�ʓ'��u˲L��fZP�?���� ,��r��x���O!�D�ދ�~�+յb������>�ntw<f������W����w'�t���i�8w}������nM����~s������͚R�w����5eMzQ��>�y�{M�J�}@�AVһ2|��!��{�Ԧ�����!� 
�Y��J �GH�/�!hx���ր�{�Br�O$��D�u���H�KA>�a���K�A����U a���P��nq�4nQ]�e\�++�?xB�Bp��<�)^D�BDhv����ŕ�/�أ-����r#��N��v$~Ô��Ϗd��H�!�]�،�/W&����ƿ��hg������@�e�,��{ڟ�<��b�����G�~ԏ#�=�ț�Y��ɴ	q����M�2�ht�C�C6@1���(#�0�	c/zǘA?�}D.������3�p��1	7�Oj�~�/�HkQ?"~j	>#ڳ�˽�w�5E��E�z���������X2�Pf!�Ba�6X�9x�%�ò�UB�ԛP�7 Q�<����Ed�C|��j���*�R&�"��c�lec� b� �S��(��)%6͗k)V��&^Hf��$JY��kI
zL�1����ӬYR���f���l�IJ��(j�pV�����*ObU� WF�q{�(h;���h�����W.�	zvz`kkB]n�T�Q^+���}�71s����	M֘;tB\^�D�@��?"{�!��~ԆS�'��>�W�s��K"Je�WM��9��J��8Qh�9AB������`�(�0AAQ�_��\+DbZ�C�T7M��,�d�I�4;3�0����v�M���ۗ��`E���ڔ�oYx?�W̢�?�1�`5�C��ÖnG��`���M,�=V��}컑��$�6''��0��mߧ��j�~@}v$��"�q�z�N؟��0�6�L<��Gxu͛���!����~�ћ��D_����C̖g�!ÁWl<��)��v}��As�U�
�&3Z�����ܣ��P�N쐬>�}�>ǣD�JI�u�1�=L�A�#�ԯZ�����T�H��=Cy>�m�כ�f7`u7?5����ʆ�<�)eۍK�u����^��u�����asr>��dGALFq�Wי�B��nĨ�)��35�ђ=ʐHƪr��1��M7@��=u�	��"�+���]"�/ȳ\�r�9�)����?�n�4LvxbO���*\���� q�{�(��s�oW[g�i�4ԫp5��kh�Q�j�a܎O� ���4e{lǙcwVsU�ht-���?꾢]Ua�{��m�j�·��!2lVvzC<��ڗ�Qo�1#ސ�_�S-3�n��3����
��,��*��D�$���m��� !˄\��.��4E���!�k�
���RJ�	f����x$���qk�
�~�b,��@ȱ�r�	3TV��&�-U>&���RLMUb!G�ƀ�،C0�\dx<�����!&x�ہ�O1�~@�Y*S'��0���2�x����5�z�}����u�I��o*��oP�u���ޝ+2W��B۹C��-�o��A���U�c��4װx'e:�m���p@4���Ypm�6Nj���8�<�>����&�OӦ��+�y+rKH~=Z�R�fשt�00�����l���CN�vV]O�z�˕�N���fs�l��
ԙ�u�F=�g%�N\�1۵n=�7F�����h����o�
��0|�{i{������;�1��[�������U�����C@���r@ץV�N��{-��4ؕq�U��y�jd����ZT�-A���~�0�"nb.z���Z��Oz�m��G���`8�t��n�y�	�v���7
b1���%]����Q�YS~M[~��ד�)`�"F���jr�@t����M#�:�K���#���Y��$�+�2��=?1��#3)Cނ_5Ѳ��S��r��%#�a@�r��ۿi�M�U.F��	�'!iK�<),VJI��:���a�X\��A�#n�<�-&B���2񩊩�������f���%��f��y\��~t$/v���k&���;<���1C<y�_����〴݀ha]��`�Z^S �����^���w<!;��3yS�D��'��o	+pZ]�������~��/���^�F�Pg;�I���.Tf�"��9ol���0��5Y}kj���d}E1N-c���R�'��Ɨ##̷^�w� �y�m>�ƌ	/�~�8s��q5~L3�������&(	WH�0��Fx���+���k��&Vk隒!fy�}F˻�iy�JN��6m��o�F��9y�}q��U_iL��Hs<\Iz�5�-3��,�=}�\o�X�@�tq̼�@R)��Wp%�;S��/ЀSv������`lJ����[P�~��u�ݚ �I�L$vr���[e�@E�*>/(��
(��
(��
(��
(��
(��
(��
(����B�o P  