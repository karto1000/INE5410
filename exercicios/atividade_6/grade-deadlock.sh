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
� ⊞[ �9	T�ڨm�T�j-�S/I*��@����R�8$�$31� ��ץUi�m�<kݪT�[�Z�b}���Vm�Zw��ݙIH >��۞����d�|���;f�1g��Z���]�p���"����n�\��~����p�V��� �?����	B.����1φ{������f3M�?��{�����m���jh�,�!e�����h<��������sA�/��g_����{e�(���
D���Helrx��G��*��~�b��C�~�(�2�xĠP�� ��QH(��
Qa!��xi�/ʢ�2i�!�����,Ni���=I����F���A}m0�Id44E
t�H�@�j֒ "�Z	h�)/�!�Ȭ3����H�H�JC#�c�ŀ��EM��r!ls�++���F,?�i�X��]�[YO�v�"3I"a�j0[;e�9d=��z��h�tf��2��:�삷�j��$eҔE�^��='���7��� ߿��/���_��Tŧ$�4`�2��G�#.���mpB�� ��FGe!֏���b�ӓ��?;�蟍&�$5�:�?a��FF��)�E#�7ǥ�ƈyB색d,z�
CFm�MfM�T�o�!o�t�|��L�f�e�f����$eF)* ����q��P�$�YD��B����O$��B�����e"�i��QK�mR�Q�zyll�5�f��b#^ɒ0:=�%�H���R��HcRG��~�0,%{=w�!jń_��eV()�M���x���KqE�ɀ9n��a1�ɡ
�rxBb�w}1��	��Ί#�p(����ò� ���מy`_`0ft7��`�&\��:�Tȃۿ�E�@�o�FⲊ���H�'�M�:�U1v�z.{��$���d�	`�����*"ȳAF��2g�4�r��4�'b)	�\�
�a����"ƒ	&&5�L#5m� '� M��CrQ�a���� ص@&S"�+M�����!���B x~f�߸��?W�5�zZ�-#�d>rF�"h������hT�}}����e_�E���\���L*ڤ"Lj�.�D�\	N ��b,&��7f-�~ɡ��@c�#U���؄��\�p����
�@�l��h�m؟cIƖ7��!;	)ھ̨	3���`��2 cy��Q�>��(�HG���c��urm_�5�p	rY^@N��%�?S������gO���rv����˩��~�o#R��}�Ei`H��[�Dޞ����� �@�P|8��P�fV��ey�ai�Q�cYj������>����H����?�<OR++�7'��C�#�f����&^l�]
��"��C�{3'�rn=\p��͵$V����c���k@\ԀX%na�{Dn��w"�E��O��X����$��w�Vȍ_�OYf�S�Ce��Q��00^2�+�b��M3rao-��I��Ac,���ӄ�&D�z���c`Ve�`$���M:��D��e�`IwG�\Tbr��d�����Q��7�T�*��\�dH�z{�A��Z���m�U)��������5m�V$���	0I@�V�߇�Y�7�| U� ܴH�Z��<VEp[T�?<)F�����("\���h`ט��E�&<���X\1hͬ��Ig4�c�	��P�"/�!�,*�/)9<1�%� )΅IF=h϶L��6���+��MQ��2X/s���K��\��C�3R"�)���%��|��:S�\&��/���)�˗J�b�4n���0<ي��!�a��8�@.0�\ڔ�g9�ל���a1�N���u��B
� ����Z�E���ٙn��3�
R�yU����p֯�@�vC�ZO0�'��aK!�-��sFcu��,!�x��5(z��fp��z:���D0G��ՁoM���@/G�1<?��i��p�46��B&E�k�l<��\�Q�i�X���+���!2IO��G�^Y
���h$��yx$F1񃕡r�D���9����@���
� ��P�~Np`���!s�}j�;�Y���z�C�PF<6a0�>d [K`T�Ʊ�:�o?����e��9&duL�s>?+�Q&���\��("�6�tY:|i1��NM�r�Xt94���(�S/hWH�jn��@@N���T�$/��������/�D��x����9�� �F���I�\�e�>�SQ8���a�0���r��[(X���fc,X��|{D���2�*�OC\��(��Fl�#��tl���{}^x;A��Jga��Ԛl;�xf���wSau�L��hg�e� |��B�=�
/��Np;����_�����T6E�R��bI�X��؟O�P2dqzI(I$�"�f��4EB�d��I��'���1k���y&���(O���,F��sm�
�f���,�'ʀ�[Gq-����E6�#ǣU=��3� 1��R�	���� w�O��<�o�X#dy۹g47#��^*�����$�F/��PO㠶�a��B���^*�;6��d���[s�ф�	}&m2@Gŗ?w��3�>H����4�I[@+�z������8�e���wi ��;7�x�F�*F�X���y���n;0E"�9�)������^����nT�m�R�`����R��R%+���+�"b�x����*������k��Z��sc��\>ō����0�"I��uh4:n�A:�0�j2x� ��Y�L�-�/�;$,�A�ꫳ�V�}���
��{�"�[���Ă�1�M�P6~��=o>}{(���e=�%}���L:���A�p�Mo�IL�˂�2�r�e�]�Y�;j�q8q�ZW�Ն����ߞl��]){���4([7a�vԹ3)�mg��Cb�l�6h�5@�v���tXs��`qt=�U�q#pSʫ���o�"�f٪~;�Ym��e�ح�Ix\���_őɪQ�͚	<a�6..�09�,�=��n�@g��,p����p���'�.�n�f;u`Σ��AS����vpGޡV�>��}�M��=#^%��U�9'vdy񖬰�iOz�ٿ���滵(��:�c��ap�����ӧ�}ojIv�Γ�&^Tٱ���_V��roŶu�Z>���8�̽YW��~�h���@�c/�^�<4�Wv��|�ѹ�)�"_�XR��r��[WV�	�Q���d[�%��?�.��k�3������k�y��]Z��9������b��Z��MaA}NU{�9~���{%��?���ZI���{F�-?����T���G���8[67�)TMY6�����7�����b�{��<}-�Y���#�Fd�ʏ������5��+_tK�Zd�\���D�ۮ�*9�,Ҝ���ǃ�Z����N\�帕a�oM���9������f�^+z������|4h���������8eБ��ڝ�~����ߎ~��ٷ?��e��
�#�����˕����9K���	\3���Х{^v����ʰ�'�=_�xz�b�uU^۞4{��X����$k��;��Hm+�[���ێ�Upa����m�E���6��߃�6{�d\q���Ү�B�(�w]5���k�_�Dͽ�z����ֹM/j�*�h�91����B�n��r��	�;�K����}L]}��YU��]���S�;]N�OV��}���tI���H��I�V�=�T\�=l�M�8!����i�bb�~Z5uM��N�7V�5A��Ѵ���Mf�4q�К��R�v�o��dXIז۪6z���7%�n��/��G����������[�T����K�xq����]Ҋ\��W�ߒ�~#���i���#v�v�>n�[��W�Q��7,"�����T9v��K�˲$_�?�������\n�o3��+F�_t�,��䋀�����8y�`l�"j���c�g�i>N�q����/V�^��4����v}5˥��w��Xt��ӸC{���Oz�]e�[t�y+�k�[��&�E�Xߡ]�[dl����K�
�O�:m�=�y|�����ێ��������I���}����r~]�����Ǿ�]*�4���C�1�q��W?<����N�լ��>u���������[W�o��Ѯ�k�jOݼ�����_g�>�7<X�t��x���������'�M��{��[���/���A���R��hw�7�3��n��eH�՝��ya�k~V�]�se��k�Ke�V����~�m��'OLqr߁��ɁY*�C.��q����~<���yH�.!~B�w����{n���{����酥��u�P���k#�Fl��%�f���nn3&OҬl�e{�G2�{:��X��$l�\��u뿻zf����N��tu��l�kS���V0J7J=og�G_]]P��ؤ�疅��y��Y�ϴh�}}��9u��ߒk[�T?�;i�w����zc�+q3g�c2.��u�G�ֶٜ��j#e��W�[֩�,��'��Q�g:5�Â#�m��|�������,j��~�wt���򌌎7�l�?!���M���c�¢�.�3/�q��/'?V�T���ErΉ�=�Owxв4�z��}��Z��b�/���}�s^�3j����䨧��0d���k{(ǿ0���.M:�l�<ys�ϰt�6/l�9hN�_]�~��ܝ���?&��������%ʑ���>x�ٮ���|깇y-�;�����W_�UU⽻x�H)�(�"kbX���W��l��L/�G�O�P����M�9*�Q����k��r��VP7/b�[Q�������Q��*/����t������|��3^-k;q��vC.�u�i�a�JA�ߗ/��������͛�+^߹�����Q�s;��L�\yzT��$��Ȓc7G�(;҇h�a��֑B��Wl^�3� ��.x)���1G����)kb����7��E�k:aF���1}L+Ѯ������������fϻ?D�nm�D�+6O]�У�%��E�����G�	���h����&~n�>tRgW�׳��c:Oj�o���O-k��*4����;]�(k�ݝ�Np�A����������ܝ@p��v�3wj��|�-���z�ի�ŧ[��V�`:��^��.�u�j�먈3��P�k5�5\މ��< �ԁ�rt����(�_��M6�S0��(��r{nfOoڰ5��,؈y��kyl�0�D��X����:�k�����h������ظN2�Q��0 ǣQ{ו��E�euQ��>��5_���@t�<D�E���`\�="D����҂�y�M(�O�%8Kھ�x+��������d�����͇��p���g�6����g�2��&��@r����a��޻�gc�bL�Y�IXl�9J���f`��
&8�S�9B��p��co$�����pW��P �Yb°�S�����t��QQ��#4�y�]�/x�oYb{"t�����/��!\�.P���D���♰�D�����R���'C�#pk�a�k-.3름n*_��eڤ5���3%��u�L�6P)�*����KSTO@���Fg)��9�4�����KD���C���#X��50+�h�0���\���ג �&+�Vt���M«�kg���� ~�xX��Wv�-�$���i��aF��7��QW���f���8H_�Kv}���	�7s�,����0ڋv̕M�V	�b; *>�//�Ʒ?ޫ�kZb@M�%SP�Bujd�Y��:nQ9��� ON�o��=iQ`�|�� ������ǻ9��Hf+o�J�6S���9IIacU�ti�s}��t�M�d��]���t=8��_�hEV�tKx3��2u>���ڏ�=<cȁ��f��o�G�!�[c���6nL�e����V� �|y�^���=l�5A	�p����*�[,�{�Y�.o�G�ۛ0��0��[|a|1��6R�_6M��&L6�}��ƍ=E<_�[����y*�T͐��Q�c��~;�Y6���M)De,�����r��W�`[VةW~����F�L�p��nff�7�i��1)5꠵��υ6�yP6�>^��W�Aq�����m�|���ˍB~<�띕7�u��A�
����0~�Q�k��z4;��E+Ou�/6�W�����#:f GS�Of�$臓�5ǣ����t��0ۉ�_LT�KL�8�G�v��p�"+�D��U�ܳ�ޘ�|�xR�f���RE�ev���bґ2�/y�H��O7@u���e�Ul�GG��|*,��n��j���og3yV�����n��[��j��kX6������� r"�1���T�d!�HD����G�P�މ���M�`�9���#w��v���a��ގ�3�]�w#��UA?%�)���/3���!k��ޕ��N����3gt��,�PR����i���>Jw��}��T1.:1�#�|r�k>S�H��b�k�8���h_S@�)$�4ƺ�����eO/Yp��4��-������~ ��\ ����u���G���dゲ��"�>�7"�<2��_����-��Y��E�0=8�5�)*���PYs��%��M��plȬ��x��F�h�rKUs�����U�Xƹҳ��ò�es�	_�[�e�4V������Rx�2q_�t���A�\n�B����OEq���<̨�qPtb�1����7۰Da79��6!���^b�1�^���"ke@�#�kVmZ��<�Q��'�;�i񢙁#x�>���N��]Ƣ���&�b��Y�/�b�{=(�[�WH����#:l��T[㝧Vi�:��F�~߀~��H1)�J4K� b��%�v�x��wx��]��Y���lМ�$������\c�?�B�ꟗMVѻ)X ̾��œK��(���EO�O�C��^/�>_ʆ�L��:�����ō�-vׁ/�d8�C����;�=Q��>��N��:��N�J��c�{m��Xh���20tu?v�+���<�^�1F��g"DWԒ߱q,�r���9�ˠxꌌ�pBi+�;�t�Nq�5fO�$��x�	[����?
�����j#�xGj�6S�#@B?˛��]=���������
p�h�B)2��ījD>��ɝ$)���)*���s1�|?p����.� J�}z8$s����?38Vl�Ix{o�P��J3-s���KN��sQ�ѳ��Z��ώ+o6��ڣ$����q�+���M�zoڙrL��`:����쨗�q3��8˭�tz�6�z�D�o .�6�]U2�Zd+B�U�K��U�.�$�� �2'i�n��������1er�����Ԅ�CH)�>�����_���E�������� ��[����4����A��S:�,|�T���������y"tjt��xb�mW��U��/�K?�ׄO*�����B��;o�.a���WT�&�.�� ơN��m��G�S�r�h�c�k_��R��-%~�<�Л��6q�RP����H3E������ɯp��#= ��f<�� ['���Kd+t�VZ���WL]�3C��& o��S�,y&%:U�����|s��d��Ѱ`O{PU8���ZP��1��'��I�s����	�*�%f㰈&ا��=	�q�	�)���r��,�o�L��5�זd�Krq�$Ը��֨����:�n��5�t�X6�ߟ�TΖʄ�z\�;~���s���M�x�x� ό׹v#��Vn�Ja�������p�h�����I���J�|���0�-MtS,�ѾK�4ŀ���3RW�r�+��ă&1����a΂ihj�|mc���\.�����J`��]�C��Lu���׆�eI�z�`J�+���Bް��;a]�) B�O"3/�룠Wc���.�|�\�>*�kCQ	u_��)Ű�{Mɹ��F�h*q_Φ�x:��>2�{7Z�r�S~Q&�]������R=�1�;��U�q��I2]����o�\����&6�w�)�Xx!��^�iM�9�S���P�E���im���-���I4�\�,�U0
�06�u�d�:��)!�_Ԥ�'�ָ�O�絩��4:��j?M��o���0��V�x���e��R�DBl�{��C�u�`8E�N���c�AG\���#�+vſ��R�?���M-�ۡ]M�;��<���W��j��c(�χH^~mn�ɏ��D�:G-�0\4!1SO�qq<Qx@yӍ�͠�b��>"�g�&���?<�����f��k�6G<T��o�Imub,O�㮭bkm�ˠ�"�tԣ��^��Z4V=��|Ȅ�Z:�����Gtt��w�<�U�Rk'��c�X7B���(��	�@�Vh(�=��"���X�H!�_X����Z`k<~y�ߙ�;�;�>J�8�����V��R;u)�iv|j�
��q����v�T��\�HN6�f~7�x��O`Y��k�*�ҥ���),|�+Zز��ӱ��4f�1D2*Di��Y��ep��67ތ�b���'���2��x����_*)������c1"�$�Q!M�D��BdaC�/��j����;�*���{�UT�${>��E�9��quee�T����O	�{�ǣ�-�f�������^��m10��@�:��J0~o�a
�f�tr�gN'��=�@i���R��/$ޒ2����oI(��R3�l6��=���I�W��b��-�!{=�����Fe�_F?�bK�j�ѳ^��&�Г��^G�̟�&���Z��0;��ke®�%��w�p���I��~���B�ÊHs9<q��'��8A���QV�� �O$9��ȱ�9�,7�\=��"�RyO�z8��k���&Y���s3P��d!R��"���$��w�����2Z������עҕ�m
����ϐc�ĸ��h�?�Ζ^͝=�M��N��N�Z�g�^�D2ڊ4E�&������81�ş�S(^�-bU7�-@��,���
­6~#�����q�Tu1z�mgw�i��b���h{�Ng'��˪Dr�Nn����R#�6����Td�V3ˉF�)�ŉ���`&�;z|\�
�������zКʏ������������)������&�>�[�<9�����S��<d�`���w��m��Nֻ-�21�[9e�:�m��������yT�����:A��mX�cu�)uT ~�n�)#l�ƙ�X6;��"�]$��R�V�0���/X!�w�h8�14V8�vHb*�W�ģ�汪jB(z�/�de�'�x(�좪��+��z�H�aמ�rS�Rˏ���o5y�Un�CP]�!{! �/�K4,�9&�:L�x��,��<�zM�oכ�"'��ٷ��+��_��6�j��O.cg���5��.�:M�W��ֺ����pO� �ׅ0_*�_|�6��������f�U�|���G0�Ń����J�ʦ
%�h���yb!������^�.�c����kN�f�N�t�C�U�;��X�'�[¬�+�8��rr���N(���~���P@_����iA����"І��O��_�A���ǂ�����z��ڏN+~*;'2���|_�RQ��J3W'��x��$��m�{�yĊ��z��0��f���n��	��E�D�ѫL�#4�o��\���VO�n����S�zՕ(�5��a���M�����\�+e7h]S,w��*t������xZ�yx ׺�o��&�nk�!���Ԯ��h��c�[犖K�x"�s��,����w'�-;�M���c(VP��XA�/izj�*�%SEV�߁.R�Q[G��Cx�<��'d�늜�q�uE��Y]��lÅ)�څWo��-t �q��H ���Q�Y�G[7�;�igW	���ޯ�k�2�ix�i�e�4�&f�r&uiSG�k��}�VL�Q�7t�z[�x�%��U��+uHÿi{5�P����|�,�W������P��	����F
N}��b��#H�uG����;W�^�
L�2�@������W=�l$���� �Π/
�":?����g���ueRǘ�+w�#�ث[@���
���p쯇U� sQ:�W���hoa���-��Y	�ISr��^��s&N��D�B��_�ݽ��&�ex.�@�f>���)�T��M��zj,���Ԧ�7���hF;@y��E�)��s�7Op^��!��O����vA�@�9v��UnL+v�%s��Q��.���S�#'���y��hY�de�CV��O��d�M9{%�^��*�z��!���J�Pk�(˓^#M�c�!���0�k�S�9�����<=�+�g[�j��޳�B"�A���]l8��3j�Un�R�hV�pZhX\[�qq�7�aWfM�+̧�z-3v$�峆�o���>�D���h�Ml�}��K�g�'*�|�-8��і���^:`��v�E�D�]��<� [�Z����|2������ �T1�Y�n<�z'AT�h��{�*�}	��1]�m$���$���=�F&'jI��8��$���}�b�Mw7,C��V�����ݷ5�2,�/dRz_	�Y���/QY������oNqK�ϔ�d2ù���!{��Ie�E����c�_�<3��Y+�����a&M��j3����w*ܡ�g��ʾox�ø={	�l�F��E<=2*o^0�P4�m�<Ґ��w.fa��c�^���e@�/� %)%K�ʶ�ֵ>����h���V�=q���������i�iY��υ��}d8o��$q{X%��0���|+���;�ES5r�݈��N�G�ތsIƼ�m�Nџ��W��h�\
�S�]��p��~>���o �0�Ȳ���$Wf_�A�y�s3CC��E%�§�.f��4V�%��� '��ŷ��,�"�Y�!������������~� �j]>�ע+�y�b��rӺ����Ƕ�mkG��l˃��X��� '��1e�%D�]y�����$����
��a��7W����6�:�l�#������0S6lz�{�W��\{�٩0)�vp����bܬ�l�D&�q��G!ck&�+{�	NE���8����*f�i�DH3tH�+�|+W��/���Kq��X���i�U�4锕�)�wJ��v`(�Wq_O��9��29%��~�3�}9�����Ԃ�$�
N+��5�m�}H�� �� �*�f?��5__�ݯ���]g%���*��y�a����C�F���ĒNa�s/�v�]�d�3"J�S!��2�E D*%�趈��PݑBwM�O����V������T��+R�^���˓l>�>��CEZ>��8M�p���y��-M�-ӭ�0&]D��{���V��]�����~�XVArR~"�)�)�E�ޜB����]�f.]��)7���|��,���]T�x��j����3�w*���ǻz���p�:ϑ��V`��$����%��^�˹^�X"T�-��$��&��$!)��9�7r���.ȅ�Ī������&o�ov��¤܌������	�p���-���=A8���M�0�+��@��M�P��>�֙�^m�q�cR��V:SH���$�/���]��_�S�G1��5��6�c'��S��S�LV܁'# b�<@��S���N��H��z�zݑ=gCO���i!��/(T�u$��c���e�0�t"��݃H�e���ʙ�0��(�t����z�D{3F�cz�~�vf+~��5������Lb�"�qL򚛳l�x�\E�����Øm�Y�fBg���7>:���_��6jl.H�Cm�lR��"`���4������6U��CK�Co�ҡ+S����!�j�O����#�Q�#���k傤߹܍כ&3���nd�a4��)������m��
�
und3����;��gӤt��k&��Zi�ܻL��k���wEV?=~�tC�����n�xր�-Nn|�o�`��N"Y�X7�һ =�����J�
�����y�$�Ɩ��)q�!JF$#�h��7��M?�n�ʑ���CX}ѽ�YR�	����EU�&���L�������m����=�����}����z�)��f߲�=r׉�`���3�8��R���B������2�r��3XDt&7B#��8�����(�����1X'�c�S��yN�kǥ�*+�� �p��\׮ΰ��+tC��}Y��k�.N2tByN�oZ�zjlP)���2�֟Ɩ.��8u��/>H��|#I��Z7��ev6D� �%�Լ-��Jm~ݛhB)�;^��z�Z)��� Y�y\�o�L�k\vӳ���J�nZ�]f>܉:b�(���h��ݰW�����)��\�
Q���P���繎�-�4�]�(`U�>+w�]�����>�l�}"��'.$�����<G��<��`�/����[��f�*W��[�.�{�����	�b�q�}Fo�*��+hˁ�E�r��:�&X��/fe�6S<�Z�.�-g#Z~w�1 x�CPZ5_/��Z4@02nׂH���&��q�E��jJ�\l%���X,&�o�LEB����/,�y�pl\O�8�r!?C�dS�-�ߞrJ�Q]������Wos�VAU���,{0�*Dj������CDa>�����'lNR`u���������7Iο��h[�=E�d_�������%���C\iQL���=nO}zS'՚��c
��Q��Y8�h4*�oxTI8RVY�1s˖�/S��X݆`�S�z�cۥ��w�ޑ� �!3�l��"x"����˅{�<��V�S�&rPMCT�|�=�Wgz]��H��>]�.�RQ�WD|h���p���*�l���P�e-~�q��i�[���@��!&��ȶ�l��^��+)��cq��ґEG�ѯC���w��2$U%��-���il'�N0�h��Z��EE���ɪpxE���mq���q�n6�9蟵�-��'C{���o+��^�������s���R>������ߟ�����O���?������ߟ�����O���?������ߟ�����O���?������ߟ�����O���?������ߟ�����O���?������ߟ����o���Zl�j+6�k�}4����������a�YT�(��t�MG�W���?P����άBz�F��GfG(�(����D	4+m�����s������������k��,�F��vl(�SKa� \��a�J��W�'�*6T��/��D�K�}��ȥ����Vɾv�E&����YⰥ���5�9�K��wPj/.A����i�ʣ�|ۿ5c4��	O"%3�X�H��,�m4&3aJ���UH�%KdI"�
Iʞ�I��kB��X���=�w�������sf�����?����̙s�ϝ�C�6˗�^<��_h�����۷��ĩ��ѷ��Jd���r�E�;���4���$3Q�:]t��'�n�����BM��

����w���5E-���ޅ;�S��-}�O3щ�$:�ޮ�_P�M*-#��+\O럲�e!��/��ȡ'z����5i��PcI}nsRH��c�@_x�p��E?��Ls�]0��k�i�B�q���(�c�p+b��a�:m<b�Ft������lk>�_�0a�f E��s��O�r_�Rڲ�ݳ�8��msz�`��*c�Zr;Ovd%l:��~�o��M����TJT�o��ls^�C���-鶒'�b��
���r���#u��������%�ε���
�S^�k��|�8�6�G��zK}���k8/�Ư�1ꚹ�uA�k�V ���K�Cr�z��nٛ���o_�Eׂ�?	�=�w����h7��{e������	+�@uMD;��d}B^(�l�^��1{�CV���0�ioLM���"����?� ��iS�Uv�O��,�s�����ז��$<���	W$���ݹYy���\,�˓�������ђ�DЍ�w�y�����;-�}-m;w�P������O3���@2,���Q�M�w��}��+2Z6]9���(��B����wq؃�U)U�ԓw*sx��J6ib�����i�h_�BC%��]i�A��YN7�/G�Ho�̮��S=Ѭ+�SH�*�ȇ���\��%Gۥ�ێ�5(�/9(L�P�*wDd�"��h�+���?����GU~��v0�� T%&['���Iu�	�Mm�-��/AY���&իH��EPN�o�a"/[q��k+�cv�z��5�O�+6O�8��=����J��[����2��EYk��-��xnǍr��
�y6�/cғ�Ѽ*cI��k��f�4W�C?´й�C��m�	}O��_�"[1�
=�-7�U㱝�F��b�gT����{�T\U��{_�1�q��i�?aU�I�&;�%̧��Mf�����m��,�c�eKY׷5�~�#۲Y؁�	���S���?i��yYa��P�6=�'nm�l{����{��6m	'�g�u��ߘ��?D1 f!��������W���߄�����C2^�!��3�40�e��\%R8��ڳ�k#��
��6q�ҳy��z��-w�;�E�JBv�v�p'sh�B�*�T�ĜVQ����%�lH՚����Ȼ-(�#���]��B�~wU�ܓ���2�v�0z%m�������&˼G�!ҞI<x��H;�<�P��h��H�� �l�����"�}�Y���m*W�'`�Y%��J������[��G\/�uNd ���E�A=��9V#�}A~da�U�kU�bT����|�qO_�HPfJ��׍1��}�{�bfsCl��L|{���Y}��g�������;Kb��6m�29�+��D/*��N�����8�E���w��1�=��!JF�P���8�sc^�_>E�$�ޛN?�r�!4�sl��Ʈe�l�ڢ�Jg<�tmS>���IH�Ϣ���{�Iȉ�����AXD_���^i��6���m_y*��
BE������k{KkD�A�������jb���#8��1n5����ΡGZ;����c�m�f�~�r���c#��A�c�X�6N�Q<������v>^g���,[Нy^�$u��fvİX� �V	�\>���DV�¾C��;���r��eMR<��
�f>sU� "���{�*l]B9�ʓ9�Fm��:�����b��Q$�:���Ri�;�
ܛ���:8�wZ��$����X��۴QW�4�+�b�Ȯ8���g�/."��;Ʊ4�2����-����c�gF���J��9{LuT ���*��O�a���Ō�/o��k�����|��.�F�#���(���n��䱄C���\�0@Ǯ�N�}���V#'^ٟba�\�ٱ5�wV��ٽ*#�Q�.i=�]�]yg�\�n�ǖ(���m��vj���i5p �c'�?��sgяs?�E}�d�2ix�1 o汊\��a��3_�����ڄ}�c��,�ӆ����&�O���)�3���u�/�>T�����r�[M��U�o�O�.GhH70���읾s�9��l���_�u{�t���MbTU�j�k��/S:3�aq��)�
jnt����k�>�3 S�Q֨2�^�~b~��s�޸♩vv�}v��{_HJ�"��P� ^�Z��d���o��&zP''��1KM�]qu)�c�ɩ뀼Û���:��⑘�c])9WՌ�45e���dc���1�^;�9<�߅�yg}�UǾ�0��Q����w�ԓ���D�3s�\�AO�����{f3�:�;�	ڼ��[9��Y���q7��;F���ON+�)���8��5B?O�K�|�&��.\xD�I�{�p�bϷV�٬q����]d���f������̓��9�Q 1����0FCU����9�5'G�]z#���i�P!ܸ;{P�VWz߻��3X>�M�8W"yc�,��wW��١,mD�;a,u]r ��p��nq���0�~]�RP����o��w$9a�[�8�ix,���V��d[H]��Z�a��,��f�H����(�C͝>-�+m����r#�_M���⟑��/m-S2j>'�R�g0ȗy��~D��4oܣK��#&����[�D��(�vZ�;)K����+�3Uo,�ס�Ѓ�)_�:�������TÀ0�S����U ��&�ꇱ���y�q̄�ã�� �Cr�`	Y��."�&�f��VI�Z��>�襁|�TuJ�'T�dA��[(c���kr��⦯E����E������^S ��_�%�e��_���e�%7���X����0�����@���[��VY)�b~�MK�* K�C\�]Uyx���U����˖+奎�zV�-����d��.x��zIX�H �]l(��
��LPS�R�T� ��d����Rk��
 ��*�])���&��9]!���[a<@aF!a��w�8b	0@�BeYH�2��j�Gܒp~م��X��v:�w[0���Oc�����Z�O�;� �_$fk&�T��D��-�8�q¬��C6��*�'�zN�u���AN������~�L�����;�Ż�.�Y�2W
��Ɇ��i�a�k��?�[�I�̿���Z���	�cK�umK�Fe��uVL�*�]�HI��Ł������(@� VT	�'�pW�D �� t 0�w�k [���P��Z�D!�0�Q��(RϕV?V�R���X�������B=�=?�<ϟ���^�xA�.�p �xGyyy�(�� K��S���tQ��h���a�oŉY�1�_}V۔^!`�g��dė��F�q�I�[�����_�{�w����7l�lRn����m�Sr�F�K��n׉�&@�zàK3��3�c,�?5�V�QiR�-	��@�_�Kk�b���(�k,�d�Nnw��݃)�ޒNbE�������l`��6����HB �  