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
� `�[ �=]W�ƒy��hC,c�m&��L8N`�Ifw`u���ؒ�$3~�=��g�����c[�R�ԲÐ�t��ꮮ������.I1��s껗+�|��׋�5��|��P���������F���F�����Y�z$��8����o���b�i��+N�?�A�U���󿺶�4��re��"tz�~�x���1m�_�����Zc��x8������ϭ�{�ʹ]�ww:��Nw�d���*m��?�,�����������O��Ώ[ۿt�J(>���,-��'	�J�^������B��'����,0�V��!р�Y`=��("u�z�f���y_�>-y}R) ��%�u/R>���?���ސ�Fh4����2t����d��`yy�͌���K�s$O%�F6!3.I?��WIL)�;*��{Zֿ��7I�r��ƋI���!%V�(��7��>��BƦ�f������zZ��r����hk�k�9A5 ��߷J��ޑ�G��L�2k��E�A����8��r�O���/Fӧ�w��'aR��� 9t�,48�v��EG�&��x����(c/�w�3����Xn@_�?�]���u7�c�Ǥb�O �c���Y�\��E��KP6�~�a~~~��Q�!�pɻ@L�O���ۀ�K��P�6-���^��iސ���g+���ú�o��K���]jZ��$O»��8�nL#�� �zR��M�Tb�jּ.�,�M��GQ�e��nK�p�gd����['�f�����H�QyᇲP�l8G:0`u0�q���A��P�*��Ӄ� ��Y>�b�WOy�+[e�V'�!����1F���U%Ј���Q�R*�H��8%cXf��� �r��{6!��(���ON�ϖ[��r���n�_�兗�4}J���X�0ŴG‸�9D�i����\[a�BE�e (Z �wɷ���r���r�U&���(��kƿƕ��+g���8�I����F~���B�}m=k�ך�'��׼��{�Ol�׭�ݝ���#��{|�cw�g�g�.�C����4���`�oQ�s��M��n,tW"fv|n{�W@��r/��Jѳڥ�����=��c�T����}���L�Vz���9��t1vc�U�M��7��`t��b#%c?�.|�9� �Oa�`Tɠ�!G�ki��=Ж+�B>WW��֚����c��_o�7s��|Z��qiK����Dc���lYo����@�����0��^�F�S6D#��{�/�FU�XQ��3�)�s{�ėmV���QI,��ݽn5��ѵo�n�5����jX������ue�}gHk�� ��^�=�#�:����ZUT��b`��M�_�H��ت��l�P�>T k��$PN̡�+�|a��հi*�N�7E���ڰ�1d{0�ٲ��k��2�MX(���R~g�Iy6�	��W˽Q`\��hfǲA����ʂ[pr#tq%?�����"<��)�����釔"/u�'�d�b�'�nVV��D�����PڂX��%���)�aH+�N�0k�!���&��vR�`��1�������)mm�[���;"Z)�ݚ�1�o���z�G{���0ٹIf�xPX$	~
հ��8A��(������ �P%UK��+ܽ ����oO�o������;k��h��\j�kV*)l���&�dw��ޛ�~���z=j%��e�߻Iy�(��G�8gD�L�J ���)Q����K�Z�X���g�$�H�-��+��])�Ίu",�AH����Io��/G]&��u�Š�\�JQ�ZdE����\0� ��/��Y/�cШî��*�L�d1��\ ?j��"��JEQ�H�ݶ��l�8�!|jܦT��H���S�f}�pr���]#���H�*���F،C�Q֕t1�?�~�`t~p-�הA�46̃�@�r|eG�d�ZT��w�@�7��m�4�3�B`ظ��������1�[�£����ic�XoK��U�`j�D*��z��[ur�1��?z��t=�e�������c����l�f��p�����KLsQ�O����K�c�Y���S���s�F1�,��_-r�n#���	�Mo���/�}M��p7x.�zԖ���� �`!x$���}�4SҁsC{�� �N1��Z!O�*l�l�f[c�l��%^ ���B�&ꙹ���f�Aa<�?xtЫXmCk�5����M;��Ծؾ(�&�xBC�Tz�	�4�[F�502�o�n k�M/�%f����2�D�GQshwb8bI)#�KP0�^� ��`�[2y�<�>E���e��7G����ɴI��H��$!)73�QjU|� ����.��ŗ��[��>����>���է��G��U|xb�v�u��o�1(.��H��2��0f�ƾ��l=Sy�A+�s�R�:{o��PcK��x��JĪ��ס3�,x�����0�6P��hv�?wl��q�~{p��o����w���������n��h|��~/�pZ���`��1����������Zv�7מ���2���'?u�v
����>��P�JfX�C�-$#by`�	���u�͏}sU��U�|@��8ӫ\���P��S�P�!�0)��d5m�G�,<Y��q�Ql;1�<�=�c�� U@�Օ��n|WW��71Ń=�	h�a@�~*E}�\���M�]��^p�O�N��H�I�xݣ�c}G�V���M �:�iQAD6P�!� QL���G���=��2�DT��#1ٖa�o+�pVpJ?�F�O���yD���TKB���"4c�H����Y�
À��9¦���WT����g�&������f�[��\�O����#\�,��b���M#�	�_�48�o�QQr��=d�B�b{��P���3�a�?���ȋ쐺�0�hZ��*��`�ǼPn}DU�x&�T�F!nU��L���G��Ӥ�Di&���9�d��3''��H6q!��SpI��{���!��R�=7�q��#1GFZ��oN�o���ݓ]�����u�i�Ԁo���V2�T	`��[Z��!���(5��蹋a�`��b�|��r>q��Dթȿ�2�,NnϜ�L{��2�� u;E��9Ym�����?T�L�JŴn�����j��@[#
���������	�� �Y�<+�z%򻻿����Wd����)tQ��v����������=>9:���@��RL7<M�9���F�͉K���\9�!ɳ��a�K�����?���g/��	c4]��"Rァ��u6��
�,}��c��������֏{�2g<X4���c�D�lj�����T�uq,�����:����2i��B0�*[n!�v�	�Y\�
�՞s���W����E���C��S�0wGLۊ���d�\7�8xLp�%y��=u����ڵ4ɛ��ۂ�G��EA� F�<��ol;aI��?��(�uy|��2i��d�p�:[Ҟ��Y����|��Q��b(�������\S�S�h�Ǘ�/��i2�w8�Jn1o�k,-1�ge۲��O4'�zp�v1�}��@��ѕ
�0��ĩ"�g��NS�hDN��I틴�[Mmd����%M2B��x/C7WZ'��L��kgt�⵪�Q׻"jӞf���W,dO ����%V� ;�,���<��dZ��i!�,���P(WR��u��d�+�����ޚQ��|�x�e����=�>�bi��c�V0����X<{9��l� A�Yo�7��F)��W٣5�*%cat�L3�0�p&�͌�m����E�X��2�K����&���Yѹ�vJ�Tt�g���On.ub�S�O���s��Q��;�~'l�2�cX�ز����t��9�s���B�mTg��B@a����B/|���I'��9�g{F���ɥ�!BBq��TD�,��j,y�� U��R׸Z�D���K��=��o#���&{?�u��G��)VYD�OԺEx�<������
j�bug��Q�+�yd�~h���B�Rb��a��"��D�E�nKS�=��_:�w[��s�8a����֍��&9x����Cށ����,�"��	h��Q� ����Uyo`L��' 
;�2o�����3�%@��G4����Jճm�3y� ��B*�K2`�Gݻ�-0�>p!��%`6�x���l�Dy&"��/��t�z�w�z�š��( s6԰<>���*��*۫S�%w�f�Y��^�����]���6S$eb��>���4�AK�/�0,4�Sw�@�g�3�q$��F�C���9�����Չ�7��d6t�Ђ���P{q�s|��H��E*�B�)���G\6N������2gX���$'@�B\��aЯX�����u�^�P�ţc� ��?�w@꒘�Ŭ1V��c
� ���i/$~p���s��#q�\9!Pɼy �UΕkJE(;�d`���Fa|�6|�RӠȚ��0�x��e&zK���)�<Nȝd��(�l�5揊N���^�G����8��� Kd}�u����t��	���&y�k^�/�rͬ����9�b����I'���F��g�cQ'1z���+���|�lF��^���a�!�.=�/�Mud�(�f��Bh�|N�>���ǆfŶU��n�h��Q��!��d�|�_v0=Zm�G����*�>�h5�1����7��_�� ��z�`�N�;�U"��)�/Y��I�^���9ڒ��d�oc&��`B�ڏbU�]�V,{���Ƴ'����˪\���0M�ؚ'W<��?:g֘��f�=HӞ�h4s�=_z�ۣ\��?��v���[��O�hwy\Q:!�k��g�d������
���;+Uv"8Yj�TK�QT�b?-��� h�uy�j�O����
�Ǉ8���Q��J��|��� �/e�>
�W�2%s3��#�6;f�2�R9��$	��hB��)v3{���!_О��g]�q1��C/�6�XmV��!�US�4$¬Ϲ0�ne ܄�<[�vg�.��PW����k�����>o�����|���/�rM|p��6�<������̫)A��/��Z�=ڏu�z��F[�]
㽬Θ�Ql$1�sf�lg�$8?2)A�8ŉX}Sq9�0BU67�P��iui��WR��
���>b�lV�Q�_u�wsB�t.�9�L.����m�w��h�{6��s<��ᑿqYƺn��2쬈��Ζ�8���寕�ڞUh;9��AaM�e�*�aV~�C�x��`���3�ԉN&_����'�";N�035$޲��jIY��*�3��1��.BN��bv���N�E�V@��z�:~�8	�K��Ћ����@.�+J8��h�~~ ��s~���/d�tF���9e"����,�w.���K��"���65�� �&(J�T���Ǫ��ul�%�w�f� (�{�8�Y��T��J#7E�U��KK|�\��8l&�>6'�~��B^�̨!���,�I��yN����q~���#f�ZW�����C��E^S���l�f���|������\��ߒ/�����G�Xb-���gS���mPb	�^P:�)o�~�99|s���E���Bl[�'���~�?E�����@��(�ۺ��S�h�a/[=
�7tJ�n�k���U����:9 D��|C��a�{����ͪ9R�p��I[H��dʤ�!��SE\��h�a��F��&�Ӌ��U-F�E�ɯ��%�$����txt��h뵽w�6�\�eyG��
�����4�'�Y���#�'^�7#�-�����s�~K3�(�s�xC�'C#0�Wt�~��?���w�	.S�GLn�P/ ��Y]m���������2����_�1�"%�K��͈�1foT�P5��0�a;ed�1'�P�6p�/#KRL� �R"�z?�c�j��k�̗=�(�vk�A�*�\Ym-Of��#-<�UNx.sWVVȡF�}B�]�!21c2	M1�c�"XMϿ��hD��γ{��c��|F��B�YMй��]�k���P)��Azk))}�ALM+I:��ִ1'5S���?EЁ	��Y��=`���)C�c6浥o��0�-Ӓ�	O&���Y2�d�h�g�1�7�ɹ�2���sQ�!�^}���p&Ӧ?�T1�}��������{׶۶�����:�3KI[o��i�!m��k1�H��Ԓ\Q�M���U������}�dI��d@Ѣ�	4�$~���<q���3)v�U+�Y[ՙ]ý+B�6'�6��wB����hsw2.S^1�4v�3LF���:�;�XyQ12KX���?o���8h���������n�+ � -fʞ�d��(7�UWi�U��te��
�{4���őo�x�ʥo�:|�D�����j��LM��зF����~�����΍���%���{�z}�+���w�4�VYt6
��i�cͽו��.��>��J��Z�p��J� 	�+=�5�5�G���oF��+KW6�a��X���e7�R�Ʌy���	�nF��4Tt_lU���)���hkY��a ���?1fA믶L�Օ���F�ۑ��!ש��U��÷q��������?o��\��%��;ܽ2��sᏅ�#��GF�~��1�Q�3�a;���z�w�q�����G�'C
���Q�?e�֨l�b���T�/�a�f/=���08�*����,g8ġ�O9G��Q�N��5��H�E���C-�bU�f%
�4S!� e����b�^@p�W۸q��#%aa*�*���ޞ�u��5��^G�7��Q����X���Y�E[�z�y�:8�>+��"�l��z���ޮذ��gy>lo� ~�oB0QA��|{*�ۖ�L&��|Y�_b.	���:@3��!9.G���������1�����D۝��I�,���ģa��94	��ԯ���9|,ϝ�~2�tGE��"���@�=��EC�7�������L&�"�����J���r���9���W�t�fG=��L����#�ܽ�x�� 6�.&�a�����d��Len�S��M@���R�_��{�Yt1����}5\q����S�~_��X��|L9aL %�4�1	n��H��,�}--����)ι�����y��G��L�ۆ�	!�N%��P	�lV]�b���,f��*��:]�a"�������=x�s� �_���J���5�4�c����R�u�aS�I�捆C�?�e���K%��nP�{�
v�r,cf
/��ey�3c7�P��(5J""q�o��@8i������b���9�H%^P%�*���Yx�-�}�|��EZ�2��h��\Y�^|�ĸ �:�Cvp���`>����B`�'��2>�����855�Y�-h\XD��9�6:]Ы�q,�g6� |x���uP�������o'��6��GM�S���x�ϐ��>���5�TM���� ��L,���<�Eu��q^��WȰۋ+boB��V;��t"Z
�m�$VyZf8Δ�� i��+�^�N�xNj�F��4w
�!�;G��3�+�'_��d�:��Q2��v��ڞ�Ġ���8O��"� c����A�2d˔��p���p�w����ᮐw�
�-y��A0Q �v����X�%7��d���Frb�rO�S�X�c<ە���Š���+-D���B��K�!l�M�Yt�i�&G@�A[��׹�ܬ��[�ˬ�VL� �c��wj���HF��T�P�LķqU�Łz94�̜�����7V����~��wp��ɠfB�]ISZQ��[�ҕ�Z��T���K��7/!��]ρo��6J�3'�v�BA6�~S�.�j�z*��YW��b�d?��N�N�N���� a݆� �  