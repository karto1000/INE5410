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
� �{[ �\[s�ƒ�k�+�4���x���t�H�����蒜-�a�����0�v�i��g����I�������c�� ���9�8碩�8�t��mz.p,u|,C��q�w+M�����ۺ��,�f�Vkyyym����z�V����\�E��KӒ�XDD��P����p׽�-q��X���]���yu�F����	O�^
?�p4�������_]]Z�E�����_\�wn7���q,������)������z���l��v�˶����y�)�8O���/�7��S^u�|�R������r��'Ǎ0��O~H劖?R��> O9Dz(�ʆ2G�jx?�(��x�#)~p<J�?��%������{��������!�~ U/��#��S_S�H%����%t��W3���s,_�4�a���X?�߆T)��j�(j������-�O�T��+?���wN|"�44�L��?H�d�!l��_Z>��kk+7��QJ����������!���������j�a�9\�^���3_k?��#����7�����"��ќH����0����A~��@��ܴ\�#N	��H�d���"5RQ���_����`wL��9'I�n�\�2��R���e���N�S�"D�Z�������;w�[����.�	����x*��ѶU�i�M����8�B��ݝMC"���+��^�Z͈�g��w����`�����5D3L��t�ePU�-�Z^��(K6Ľq�(`��l������N���yo�ӜNF���R��p�G�8�yɰ5�tj�����0�ì@v��{�C�L����~�ZJ���s�`�G���&cc����i����ِ�\~���
�S>&�����X�x	�F!��(����z�����^i��7����R��f(�y��	T,=��*��K 2z%�z
i�|��,�r%�5 lZ�j]�L7z�f��|V-ѣ�@�8�G��2����|1�=���omm�f��1�9�{b�t�����A��4X���]��5[+����V�&���'O|������֟���ݣ��.-5����|��H���b*O���Y�8w��&���~��Тc�W�M�#3m�YS;ETn4h�sEY 9ä�3��]Z�>��w�{pХ�������%:�K���rv�ѻ�AԻ��zW@4�O�R�FV�]Ѡ����]��@��a�ݯ��E,�nO��px�0S���\Y(@\#vi��_P�[AR���=��T�g3d�N�]l�b3�J���������|ۋ��A�����6��*
E$}j��R�A�*͔���]��Q��f�@���1��X���\���5���>�3T>� i�h{;���ײ�P��ԨT̀f_�c�j�Z����cc	ya�²�U���� ?�ݻ���Bc��t�cd�	���G�� u��c�M������Cиf��������|3��r�?	�����݃��ݽ������;Ybp�ŅA!͹#C�0�e�qZ�^�9��~��?/��������_����R.��预����-��,"����?��/c��*�Jʦ-+���^�Ɨ���ZѮ����7���f���Ỳ,�{�s\2/��d���q$4���_O|W�6���1.Z�UN��	�����3����H��_]^Y�?�]^^����Q6�l�?=�8��������ag�A$g{�˃Nm`v����$	����:Lf,8����$��c�ǩ"�1��JS�%O�� 
qH�N�-��Hִ�K	���LA�	�=O1~c���H�9}�.�`̾�? �X��:�+���fJ z";R3
�>��0�3n���WD��M~!��&V^���e��
�]�CT���7�#�\"9d��z����\�
��8����]lA=�qc�E�!��]��D�Z*����6����&5����U��!�S�ٳM��ÿ't��C�Q^�zVe�<�5�YՄ�"�fY@��c���ݟ�N���\���B��F"�F$��Y�3���7��}���R�C'�5+-�ќ�c��j�� �jd�H�/����o��!qO:�_��.G"��1f��uw�Ҹ[W��J:�j�� �X�.�SE�;�"� fD��D���[�A�j��\�0V�`Ɍ��{<�İUu�{_���G���L~��f�U8:���P�E�;���-��Io��)W��������@�[�U+�¥�jꚒ�<X�~ �H����b3[�u����_文4}��dΏ�v���	�Gb �wD��,-���9~�u�î�ZA�&
4�����׉Q�qu���K����n�����l��J�EB��al�3Pl �!��Kc��[�	,�F �g���f��� >kG� ��+O�0���@�)�Q�ɍ���({��Oʕ��*վe]Ծ�Q��{�^�Ղ�P]����kʄ u>	�|�YӺ��z�J�S������a��z��_��s�p��~h��8V�!�mڣ\�KV���̂f�4!���;Oas|LM��5!�,�h�My()����V�4�?y˗{� �(?=EН`g�����8�z��#�B��<Z��Fb�g	Q�3��u=��R�Ug�%�v��ߠ���4a�
w4�p�������"9������k3{����)'P��)��Χ,�;Gp-�}�#Ɖ	�з�V���&���huC���
�}��Q.f�L�.b[T���p�2�:7������;�W�ef����꥜�7��lG�:U\?Ux���8P��:���~'��1�m?��<�c��v>17�4b�� Ewx+� 	5�Qqi#�Y;��8���yQP�|g>��	H7�d>�1F'�>̚����k�e5^���e���Wb$"�A4#mf�@z�u���~wck��=/��$n���w��4�e�1LR� U������`N�S�U-�ڤ�'J���Y�Ŵ��V��|�8��S��)�Xh"��������b�]���12BЬǯ>��_S�Y��V[����՛���S��2rN��7-ᜱB\��+:铊8�~�g�~�D�8�p��#x�Ɖ$"�/F9&��s� ���d� d#��WLo�? ��H��Cx��� �"�!	�� �tx�s�.�1���`�$L.��Q.f���Pt��	xt�4�B�o�:V'��i^�E�J�+r��6V�v!�@��p8\�\G��9� �����L_;�f0ձ�CC��⁜�������
�c`.�W�c2�
`	YIXg�7���U�ّ1߈�M�O�����4V����呑8ıLň�6�:d]y>Ks�0}��!n�%V�LX `�Y#�ѹ�x�(�������������X�+L5��B���YkC!��f��_	��cg��2�~,��5z�)1B7��)@�6�*�����p�q��>n�32b���r��;��P��@�I��� 2e�6��ю�7�i��!r�X��9�+��������s�y�&��2s��$ޅ�˜���˦|w9���x�9�Ԁ2��f��S5���Φ6��ȸ
�,p_�1���,#����lrJ�ܑ�/j�̛��/���������c�d��~12ri�r)l�mW�*Y4L%Ԯ�P�AEv!u�<�t'��8{��O�ן��w�v�p�4�C5p����x�R��Kҽ���N�Ѳ����/^����r�}j?����y��F����w^��/j�������[�� ,p���o���/�/�OugV#5I�1y�U�ݶ4�i��F%�.1͊�
���Q��Ev�͇E���e�
]���e�;�~�J���/.6�f\�UI�'�3z�Rm��n��z�o63B�Ҍ��F�q ���_�s���6�=o�>q�K��	��0��Z7;�J����Z$<����G�I!{���P!�@�nϸE�Ye:���cv��`)Qm��|���g�G�qc��Ô�,]��x4Ƹv�1��)6���F�uf��lmt�;1�t�j��/���*v��r��jl�>�^~�9-� ���˥���d��2w˾ �M�����'��К�^�I�P$�X/��W�H�ɞ ���!C�=�ؼ�b�̗v�o��w�9h&��gc��V���و}�ևŻ.��n�Ǔ��l/�-�|X��,����[��W�F370�[c��b�5�c�@C���5�,����^��y�w�W�so�m�~�_ml���8씟>�|_�]fĽz}����Jb�aj:���'�������Xȼ��
��,��y���h��d6�lJ�B�r�Ü9;I�ā!CX�-�P�%�=PL�#3��d~��N��Α�O�y��z| ��&N�������������B�,����]��zዦ�E�Nᣞ��9s�J��X��T��.'˶�	���7��$��(�N�4�Y9��B�9�Z�/SV��(��>��>�þ-WU���)/9����^V�εU{�k�߸�� �5�J�l��jnFWm��rLL� �����l�N���Y*���k^�!\�������,�8���|��\�t,�����FPI5T=c�#ki�Y����sB�f��V:o�aSy�����ކo��3��*��%ռI]Y1���S)L�h[y��!�T�D��T�W2%T�~�qP�{5k����3�+ƀ�+9p^!��Pe��8_Ɂ�
��,��O�ܜ�5�+��O�5Q�|��(��&>F
�����&h~l�<��'�X"\����|�)�:��FC$|j~u��x �=��'$�$Ó��OR���p���ݔ�rSn�M�)�p��' P  