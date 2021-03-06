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
� �Ļ[ �<ks�F����1E9$E�%Q�%S�,ӎ.2���8W����!���!?��1������W[�N�{/$����eĠ�����3dȃ��;ƴ��v����v���鶲�����������l�@{������u�8��+
B�g�+����`1ܪ���W��?t]+�C����������嚵���G\}�����Xe���Y�w���W�u{,,�����v�ya:�=�*�GOz��<<�;������W�����^yKy��?y|p�]��U�}��R9n-����% ��l:�e)c�g&3V��gV&��=6r��s���2<zS��a�	�{�s��2r��cVY X�)w 7�.+��Ap�ߗ�b�is7
��ug�2[7��s#�m4%�V�+�3<��J�#���1�C���*9g��U5�5��z_ ���R���f��(���M�jh)����?�Tm�O�>�b�ӘϏ����/���\��<{q𤯝�b��L<wq���0�+����ә0�#~�E!���K{�Y�ь9]���e�2ܨ�M���	�e��Rs�$D>"+Ԑ�|�s��t�����9�v��Q7�OG�A�&<T�	��J��`��ώ�q�\��E���M�ѣGkkk��n	D���7�u��L����#���*�HC��F���a�;4���'D"�M7ʕJ�ѮVc"�,��q�����ad�(e�ܭ c���]�����[_�'(K"�])�o#�3>����`�k+�N_�Z�dT*?*ɐN���@�0ԹCl�:�P�Y�s��9`0���� =d�D��R�,UK<�:����������<��N��"�#�\޽+$�BwJdX��D� ���y2���M'�7��Fg��TgD�T��T~C��57�L�G,t���0�9 "oJ0�%��&0�+�N �Z S�웠���j5��o�%����:2�{\���[�H]_M��[������������=;�w;�/����̱3�c�i�=9��І�������[�[MS��	�w1��f:�A�z�#ݟ4���6L��2�]��i�f:fX��Ș�~�%�W�S.]s��[��P)|����>�΅=(�VFnt�9= X�M�~�r!!�?v����3�HP`<2BZ������
B�{���TCgQ��	̉�,E����UfЃ"�9$K���P$��k����',fZ�?!(ϴ�=�N�ٱ����
��{���6V�s`��'9�\ W��������b�Y��&�Jc�1�JNQ5���g��#_̆�Y�����<NMx�s����S��Wj��Zyztܯ��T��Lh�y�p�wu̪��j���*Zɲ�xg9-�GR1����	�����;#�������2[�a���߸���vwgkn����������Mݦ���� Fj�o�i�m#˼ȷq�wf�a�խ|[��;�f��t�燠�q'�Z*�XK����&�'��=?:<���OWB�6D�{�Ax�c��[č0PNu0����k�"Cd!���h�	���+w�C#&Tg�j
�}vz4 l�Y�{��ˁ��~q|����ٌ��p�Ê=V�H(͆E�{-\��<(偋�1xy|�Hy4�H���j�㈜eX����`�R�Gߓ��/��	��-�IUS�4��5),7�)W�4"��3��{3�@�ϑ]�;�PS�c�v!�K�m����[�cSE�UɩH�Ue��%H���!9i;�[��P�uV�%��CUj����"p٢'�B,�������h�#Յ�$�Gw�f�*w���^�v�J�u�<�;��s�0^cQ!ō Hss,���(�*Im�ޔ�,���HPX�PZ��Y���TeW�g�s���k=�$��2�t�߷�:/�
�$p{�P���_�a@%=6Q>8�6)�Y���nsU�rL�R�$p	c�r^YL�z!1<&R�Am?��ȉ�5&e� �/��T�	c)h'i2\��T�78���q��+^Ю����8t$Tp8��k	���ٝ���Mf|ƈ+D�j�P%�l�7��h����Jc�	1v����m����D����(��g���#0�Y&��K	@F�(�x[Q0Š��l�8-f�����
�Y����8_�`PZ8`46Fw�8�B��d��In d]�SM1`����_aJ�H����:�TCn�)�6���])��3F�5)4�U�	�]OjR	����pU�񂊕$9[�
��i�aEӴX��*Ը���+A��W`�29[��Ű�\8	⪋N�i�*>~_�m)31-���ٙ6�!�Ti�x~28������N'K;Ui�#��n)?�	r%��9�;�W��5��@C#���$l��@�O�����M�K-x�R�1��>�,5u�ei�#;��|:yF��3^Dm�ǲ�jvA�+��*�ku��Uָع���P���)����*���������Fӂ9�e��aj^�X0�.��jp����Y5�41����X��?}��@R�*��O��+�v6<�<î{�Qd�]����8q+=5����ҫ��zl}�$�/�D~?��<�Ws-��2��|/9h�Vq'��x�^c?��Q������}�Z?U���.�\�PG�>U?Ay���)���xD&�л)�"���n��d�w&��js�年�9:T�8֫�]����
J���fO���j��&����67�1���~�(�f6�(oi��s��%��{��:�t���5:�:�i�w�۸w�n�ֽ:�j�����j�so��-�j��� �f��fo�����ۡ��ll�ۦۖ��	��s�n��U��2�q��)7����jS�2�)�aү��"��H��ǥ�\�B��ـ��/'I�NrҬfR�� {lc�AX��SN^��*�i
m��#P����*9��b rp'�6a~FGMSm�a$KR��i�\{�נ��O��Lf��Jw��U@�H���. 6 9j��8m��w2����O���'�3o��)]�)�u�<մgz��y�D�>���2�7u�aG�H!Q�9e���_6�-����2�2��6[���,�b�	b��3�gkZ.'�Ϊ�E�R�U���I%�9;�e�K.��$=�B�j�����P01j��*c�>���5K� )M.��E��D1��b
�l�g�1�@��4�����
V�^�S�
�.��(�_��7������J����؜=����r���\���ɉe<Q�&�L�H"a>J���:N������3}����������mĕ���U�ءk��鴤��}W��l$��ģ��sL�:y&v1=`�M[W�=�T��5j�� ��u��� ��2(�_	ڞi����V�0,�;l/(�ݒTI�S!�Μ��'YMˍ�$F�v+�=&�z]��őߵ�'�$��J������i7���WH��_�(=̙ㆺB�j������[:�����Nwn�oo�����,W��ңg=nxt$>���G�˴�0Xy����N��ko�n�����ɽHu5�ai�n:����Ĩ�t����i���/��~r4�ѤR'����T�C���*Vɯ�X�er�5�k. !0���?�Ȏ�TR�+�'��F.��U�\��@w�����c{��ý\�l��=��65���-�*�L�g]�ڰ"nwr���q�_M��u�F��F�m��y^��G�dɲ%͝���p#���Cw��QZ�"H�gV�U�"�t���%b��C����:V�zbӴI�I�X���p�
σd�o�ugE'�x<�C�F��{S�{������;�mHli+W<H��K@��-�Zv��qGBCφY��I��m�aXFw�� X�K����++�fFX�}Q� d�:�Q���P���Mj�iڟ�3��8��oK�3>�����P9����@��!���۵��*8�0����܆�s[*XYZ���]���DV����\}n��bk�2���rb,(����L8eݬN���Hl��.fYL7�Ͳ���R2����~��A7[�~W�K\�Å(��j��'�����g���x㈏\}n:T��Ք|	��[��
��&F6�)�C���0��%>��u�Xc����%��1%%�����dW�&s%��p�x��9�ߝ�of� +���ɜ���������,(��V�g� ��b���8ǰ\LL�]P���D?�;WZ��VA���a����zc�m��խ]�>���Y�,��6` ��Eej��[mv��E��k�;"���P��-�F^��S��.@|�A�Ѡ�#��@�R�����a0��/�jϻM���9~+k��c���x�PƆP@�Yw!*����ٚ�a[��,�|1�WK�?��8��]x�˂����B�� �Kښ=�%�ʢ}4n{.���:��Ko�N�	zl;S�R���ڋ�ڭ\�2�!����^68q}���ȃ�Dc�0��1Q�*��E��W���9��8� �����������]N�M�-�#�)�e�~Fҡs���7�kWk��g�Y�\��<̌�岂?{u��J�?q���i���t;����o�����Y�ç���z���0����<�k?������a�����ڡvv���a�3ս��cxS����G�cꄩ'-����5H8{�h�� P��D�|iX9>z/-�)O�O���V=��wG���^�&�ܦ���{��s��G���K7`��8p3(��d`�`�ܾ�
Qc�\hfv4�!Ҹ� �����H8��7�	�A�lu u�K����@v9����x�( ���!���aZ���S�h]����t�	�֯����B�Sc��O^�̜��CJ `��u8I��U������l"?[�m@�px��t,�6�ѥ�|��Q�Rs��A�p�
u��7�$��zχX�W�?N��Sv�j�Y�5�#a2Cw8��z��5��3��>�.��?��U����ʕw�����5 }���_(bE��LW~��N@������ސc%�߸<GxN�n�����z	���G&�B��~�av�(_;xv�⠎�x�͉`�WN���.��a]!�F]�Xo����X��eAz]���8�5#7$H|�|�m����������|�Nq�f��'x�,٪*��oO���d�T�m���y:(&�E�2k�9�����s�W�Tʕ`����B?rU�yr��*�����֜]�FC V�&�|[��P-�1c[H���#�(R���C��J��M����'�Y>�F�DqW&M_��-�ap�K/@'A�����w��m��Ddn
"hP�8> 6����%�o�P�m [�A
}!D>|�$��l��|3y;b�<MD�g���ߑa|��ށ�"���$c�n_\�f#!ɼ�)�~CI����X�<R�.W�L}��P_�!�º�g���b��
_��U�OTT�ھ��Ʉ����L�ndL�(^X�E�}P�����5&��%��`�%�i��'���y��UW)��p=o�s���&�� ���I�$G>�sڅl@DhL>�4 yE���m���B��PLL:�V2r�샟��u>c�@�b覒�2��G�'ru�C��¬���1O�0�g�+�N͒�)�����؍,5-"���k%&6V�1�]׉�ax��Fv.w���y�9V��1O����z�up�,3+Y�.��m�:��Θ
Դs'(���"��MI�J�.uk5C*W�n��He��,��J9�����2ݺ�JK��ɍ���6��$�k�	A�#u�5֤�����7��ć����\��8�A2/�y� �cm >�ym;ܝ=9؅d�<� ^:�,Ԋ)�;y�v(c��jV/bߪ(��*��5N# u~~�_=���k������gf�i����&�v�$�8�/�,���e��[��v�V|��I��'w�"w�0����m�V�x�FV(f�׭2!�B!�B!�B!��o����K x  