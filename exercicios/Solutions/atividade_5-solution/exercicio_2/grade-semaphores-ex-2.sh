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
� i�[ �=�V�Ȓ���h�X�6��^<f��gd���n��v��%_I�|s����)�b[�R���0��tN����������.��3�/�}��׋�M��}��Q���Qwcc���}���}��o��<"�ߎ�䚇��șЏn�W����b�G�?	��,.��͍��˕��y��h��q���L�/^�忹�y��t��O.��Kkg��v��W�{��nmopp��_^���><�/o�����/��g�����vv�/o�P}H�#�ey�N���� k#z���'����K\�,7B�w��pZ=2�k��Jgd��_g!i�W��l��Y@����њ;&�@�]P��O��0���K:!�;��<j�h�x#�L7$�)�������:t3���/	ΐ\J4!�lB*.I?�/WID)i;*��z��ʑ�l����G7"]��[���؍NM�߼�a����4�+Y�����������/���k����קh�����5\qoI�3(`W'�Sk����wN�У�<ݛ�z�O����G3�tt�?aR�i�U���s�E�;�J�G�b �%��|�8���"��`����`7�{\�b�}����n�4j}/�^D�`?~�?��ˍ� �H{pƦ��?>~�x��U�)��1�1��h�^Pg�ֶk���
l��4�[��=6D�\]n4$�jײ� Y������V\H I�3PW2�Ąͬ{[BY��NBZ�G1�un�k�`��t����;��nm���q��8���ua��t���a��dX�uF�����P�׀74`���?d���	_=�e�n����
� d{;3]�I�>V�@'v��X���P���g��)��2��mh�s�3��/����1yW�t}���"l���Wi}�X�%��RD,c1��'C
��"��]����\[a�rC�e �Z! k�w�ڻ������wV�lk��V+���+�����9���{O/�dt�ϟ=����N�Y��?{�����z쎽���������ѱ}:89�ip�����m�C��7������9X���h��O/��{t�� �v�jfGg��Q���4I�zV�v�#|����al�FQ�7�B���؃Y��ȟ��7g_ � 7e�~c�C@����tQziPO���a�6 ����ȟ]9���Fe�p~s/t�=�d	��.���B��AA2��^k�J���`��W����%��}7m��?�ti���u��!"�Xؘ��&�Y�(���ix�(uc�Q7�3כ���^�>�(�.a���`Vs&g�̉.z��c��Xx����f��í]�v�[�l��]kCˑ��ȟQOwF��s���Q9���p����Cg46вC���������.� =�m��� �g���E�Xb('�P��z�f���01��M�7�}������1d�?ٲ��[Ƥ��]X*���Qk�I[Y6��]ߍ �F�fS�����U���&'�-��G|'+���<<&	��HXv���J��:�cN��b�/w�(K��D����PڂX���%��H��aK@+N�0[�#���
F�v�[R��M�[5�ɞ��?<8������ F'~H��[s��ࠧ||p�?�q��m,E{�B+D�$LD�x���1�u����L���}��i�;�r�ooH���,��w���+7�0֔�2�e���MV�4O�C%Pb���q���]�������]L�8��+6G�5�b�ȥ `"Ca��O���+�N�RZ�|Z$��}TQ,l���!,�I@��'�V�h�W7���	�k�e�jۺ��F��n�[����q��y�?��20��몮�J���\"�;~��-e�͉b8���l8Ő�d�_�Z�i��<�n6��'�պ�#z��s�+X\�y|���R��T��;=I�ѱ�F��9�l�je��a�L�^���a%J&��NK\��UםU����>gv�%�xɤ P:]�7�������mp�a{�P���	�a�I"��\��;(��TGkgc��P��N���%��b����
�Vas,���*ip��ٱ�U�bg&����]���˺�1J��ϟo������{�L���A�5��=8��#������	�쮛OOX�6� p����"��m9��G�5�sj_Q�|�M�!�zԞ���S?�d��%�3���h�n@'�G:�L� )v�ѣW��܋ӉG��%'�k㞹�2�R|�n���rH0�����v�B�P!/&
��K'�����U��Ѿ�'�U�gP$������PH�ЏH�X�]"9��"P�Jb�"���⺖���#�Q�0���}0�f}�u��שu���:uB�
2h�bb��"���k�<^��/]�o�/�5����h{)R�H���ca�3r�9-c˂�I|` rE��ɠ��1�u;��T�������i�Zm���1I��{^��ۻ>�3���7�O��f�����bc3�=�<��q%Z�����x�U_Hߞ�#Xj�;&�-�OM��C���3�ĭ��t?���eu>!�r
�����Ng�O��������샽�r|u��m-72 V�ݾ
�Yٵ~�ݭ�����EG�7���oۯO���W�����B�WG'�o�]����������׃lǲ����a+ȿh�����l��o����ws�a���e���:��x�����S�q�7&Kj�H���5��!�ƌtg��0�]?�{��K�M��QR�U����	3Ե���o��L��7^Mږ�N���a�-�'�,�h&i�Yd;ZB{xfGV�0��7�ZD~F���cD�LO�v� |�F��dx&��ъ0��h�_y��)�\��ivlp||�G�I��
�CӁ�
"F���	#�L����Xx#l5$�$�r:y	�S}��g��S��-0j}��~��a>��JQ�ƪ��� TDT��潘�)��$д��eWC�s���mf��NTZ��b��������T���g���/���Ń����Te{��j��^��2Y|�z���q=<i^��VPf.C��L��:�PX�6X⏽C/��v@�� t/ir}U`����֊���<Px�(�=�Cܪ�-dV^/�C��zc�\T��pF�P�*�.����_���"u`��הA4'A=�� a�h9b.�kD!A��$��)����B"%`Z"w������X�%���ק�7�����>h��u�!h�AKv�n�˲�Pks�(�v�&�;=�}J~w���y�2(������(�QlN��h��E�-0/���Zɲ�>�fRdND�����`�G�\��Jr�Ҡ����yH���Uؒ��^�֔�8�,5��R@��������ß�L���!���:6-�9��'AB�(����%���3i�$��xA~�$x�1�?ۦ��B�/X&C��,�@%=���0�B����aB�0eM-��U���N�(�c�}���u����789=>����@�f7�XU�.�O�h��ݗ���\�Y?�*إ.�<	��f���}��t���X$��d/����=QNK���w�*�s�g��������O��	�s��J����x���z�Ÿ�lp�@8rH=��|ս���cH2d�:\
l�-nwD��k�� �^�Z�[^EJ~Lx�tIԳ��W]_<ru�rK��#���f����gf�,NWL�in��tHқ�9�!�����o���K�wp���4۲���`Iv����z�.<H��>�Y9�\�X
qy�X@�"�Q���Ld��Y����r�&;3VJN+?�RU����K鑏���O��6�4-�D�u��CAъ�F#������m;fI����ȣa���t� T�̕b�p�:[���<��qOI��	���:1L�c��ڞO�(�(�_�*F�[��g8�� d%�{j���qZ�-K�xa���uN�>�7^�`X�>��ylv�\,L{9q�
g&�����R�З��)*�u]d3�F"YGl���ʍ�Z�� 3� ��� ���E��O̲��m�E�|K}��D;��?(�I� �..�3�*��E�Js��e�r
�L��)������	�0�.c�-x*�_��)�e���A$h`rf��IPy@��ܷ�uD��	����;�s'᛽p�-9Y�y�
��2��v���Fv)�?���P_~-��㬌�(	�^ee��d2�A�'��c�B��f�e=Y��-?�џf�KjC��'*3<H���W��c���廙��Ю��:���^�f�v�R>3��D��oA�̸[�)a�ȃ�h��d.���6������S!$&:��#[%�	�͒ni
�� ⩟��0�ϼ�V�JNd\�]F}N^����:�ZL]�3����3W���)%��@��)A�<e�9�K����h4�g�i�`\���B��IG�Ȇ���1ʛ|R���ZT㴡zZq��J��,��y�s���XW�B!뵩�B�r��Ky���&�!�!��l#��4�J��8�`j6���iA�j??k�y�4Mw�;)-�(Ϥ�܌�V�g1UV�RL�k�X'����b�=�l.>�8S��%W�Ä\�()	�XH�X�{]+)�Q�k��3$�RZ)�s"="`'ι�1+ù[�i���iU@7g]l-+�.3�2���z�n����0{P_E��Dޠ:K�a�	���zk`� >���o�e��k�L	�|D{[�J����kG4ř��L�Z�r*Մ���NhDsC$+~G�mc}�V(�+%GnI����Ԝ���<��N�l6��\'�75�����s�Ϡ;�N�=a~�9/�̏ʔ�|�+7�N� G��ͼG'��c���Hr~A�e),��6d�EK�� �.0���X0ˢ�WN�)<�Y�NE p`�4	�J����3,�L;�rh�H|oC���d_�1��Y���8Wq�nn�5?!�׭4��j�dX�++$�M�������dܰTu�Q�=X���ߖ��Ӡ�Ԕ%�ے���bf_�����n@<�"r/����K���t��� � ָTo�(�)�b�S�D	���?�E���*�_�cx��S05Ei%�ΙJ�Q��d^�Z��ASq�N�"��y��M�?�!��[��_�
���7���$<ɪB��+�����ۻI����3��K�X��.*������˗#R�~pg|�Jp�����Q���������>S��Fj��*���S,#�!��лyC@X����R!V{�{���'��m�8��9d�TP����N��O�<I��Reԗ��:��Sݯcr"w��3y�[	��v;gm�X�̂�����X��" V���4�IO΁�4���ZE]-)�_�P�$s��w��Y��~�s˘378����ߨ���=VQ�|�_�VM�
a���z��Đk�+��;��W�V!#�O`�'��ƀ�������ϫ-�D�V�օ�����dIo?+�7É�ae�yz�t�ЈL:Cՠ�3�D��rd�q��Z�:�q*5P���j�O?�Q}���m��xRo�6��']��������2�H�\l����8��aNmo$��H/��;#�G�X�����>����>��
zdm����{�aƊ���:d�Z@�I�[˚��IgȾs�Tw~��?��
�T��Y��U:�V���}T��/��3����I�*�"�B���zt�2�l��*�\���77�^�I�<��?>5LeR�6���H�($c4�?��<�y�*E|�%u&��ր�}5-@�N�ϰ�܃���$ʟ���K>��2��#y��Q���N7���g�����������˝W�o � �%���3�*�I5_��V���K��J��/�&�W��,��F{VE1�D�[-^��Ъu� ���j�5ďo��o���JW>�&�_r��GY�π�KW�!�î������c���w��e:���@2!Ht��U|�����Ϫ��+͸�4�l�Sm���"�g�*�� o���ཁ�X�u��fVK�p���ʴ�8����,u?�7�Oz��{��Ǎ����=�|���q����k���}K��F�J�_����Ԛ��q����=��O#Ŷ�p�ڌ��^�ђc9+{e_�$����z (��(Jlo+���kД~2��?u��%c�Oq�Q�t�ځ]�3K�����U����L�w�Ɵ�S���'�]�?����9��=.Za�Zg��bfC�����)�N=֟殕��?{��~{L@X�sW��3�����0�@x�Ͻ�R����1�7�G��n��jp�?��v���YX��BIbZ��^�^�ˡ����0�e[JEm2�~��d��;�޶��s�+6�SH�HIN��ɕ[��hN쳝�"5��Jf"�*?�&w�1y*��=�r��c73�K.)�RS7AK"�svvfvfw���ث&V��
<����hW�|{K�[���U)�{j#���PMGf�[�(
KJ>�"̍3r$z��`+&���@���.�Z�VQ�L&�ν\��*��{�����}����9qrS`����}�������~K����;n��8�+B�갂�	e|G^�y|���(m�@��J�jh�O�J9E$y�j�{<�Z[�ʈ^�r]iUmL$s9}�ߠ������̐k�[P��8[�N��n��r�ۇ�;��.����8]h�8���F�OE�0lZB��T+��U�]->��3 S6�D�|��K�7"ᖘ\��E�K��2f��0�y�C?�j?�8zK��(�.�\,%G��{5�)�R�0Q�B
��ܪIJ.oΉ�bDh�]�N���c�Y��)�E*6fsm��Zr\^Ϟ��/n����%�&']�� �%��$gE���q�e���2�2�C�<f*Wk�^!?�;���6hI?匳ކvcizR$�m�qy�p��,4��g<W$d<�[V�Z�����N�^US��.j+��KPAԑb��FT�[�����N\lέi�ݯkL�S?�1���Ƙ�bh���}vw5@SY]"+�+J�1]g�1�VG�YU�.Θ�(dp{�џmVT�l�����V+Ͽ��+�#���#=�i��>3m���.��/��+2�Wn_} I)�d����/Z$���B��7Wy�Ѳ����b�!�k��5Ҹ"ߩ����{�c��CW���!��Ix�;���(K/(�:�r��=����}�42�s�`>iç���ׄ�5x�87}��{�ȁD��U��Τ��|��=i��6�9���\��(3��,$�%�y�G��4E�k����B���������6��]�xӶ�T����K��9ZS����H��MQi��ޯ+>��۵��=�Ro"f ���<�/�wz9��	��2'�D��ޗ
y;�@$b/��@TŊ�0���z��Z!Y��R�:P��	�������u�������rGV�:{p��F�(�x��$�5��w��J��غi�����H��߹�'��U�x�&T[�voiϡ]R���l+t��0��y�&%���L�.�*�fC�3�!����Ɲ!�__�@5-���?_��;�����Q�~�L���`��������Y__{	�S?���fra$$k獷���*��Q��,��q��)��!]h
��Z�;��
��C�[r��k���9ǂBX�+�z�^s�0����l�U��["<�?��;�L9�㰧�`��%R����U�b�Ri5唲ҋ��A� '���t1[�V!Չ?�������p����S�񻻻������*��{����Ϗ���^�a��+K�e½�l͚ű�Gl�k�/�
X����	G'���Ev�_	���?;?yv>��B(k�u=1��d�Gx��(�_8	��mQ�=H)6��C��+�LS��	G�#|�n�S�����r���@���gSI�y�"T<,��W��?�_Yx�)k���Hٞ�P{#���;�H*�Z�cas���Akc�ѕ�=k��~�@7
,J�Y��t.uݯ����G�O.���,
��$[��s������m��9�nFބ7�����[Bft/o,4Dy����H@���,�B^����~4p%&0�7v�+��޽ׯ�t	6��#�\ɸd�w��W�Ot�����W��q-�U�}[�v��Ie��_�8�d�JQ5��g�.uea�K�߲,�����L�HYs����u��8�Uw6�pͬq
/C?��m_Wh�kX�k�2�:��Z����5���p�f�_���e+��	T�`�PO�qa&�A=�D*ܔ{<�������3� u�`U��F�w?�y����9T�k��Xݭ$�UC-W�4/��b��/ÂуDo�5�0F~�Q�zۭ9���uOWcZZ�v���4Es�8r�2=�	��oN��\����U+��f��3���,L�6�8UMո3��t^�M�t޴?��M�·Pu��?���#mm���	Ű�8?:c�J�*	�L1^r�r�+�Lv���PW�(GЇ
������E�s��]�r�9���V���\���1)��#|:�@~Xf�,��	izb��Y2Q1�JV�J�o#r�N�Z@���S	�r*�&^u��J?���M��Y��V���s���E��7�H�}��崪ZRr]�}��E�p�y9dp�k�ǟb槄b���%7_Ǫ���_�w��?<:���3���>�G	��Ko����:*'��=���7�r0������>8���A�V9/㉶�%"���u�
�?�'��?f�,J��
2��tB!�W;�e,l`��.��� �8:�qB)����>�"T
�1��ehCI���u���̕d7� �HpP?A�" ���Cj:��ˈ��)���7���8�3�.��V��JE��P�%�>�2*��q��Zz�!�U�N�.���j'�̈́�P��)�M�]���g�����0�o�EL��.ɉ�'�hz��<�N��Cv������{r�\
h3�1AS�94!g1��".`�_
X��?;=���l���\{l�q����v���}�JV��9H��ɸ�9�ͦdA��y&;������[2*�a�Q�0$r���D�۔<���O:h�ı��`�<a�td��$�LRvZ-��D�~�Wh��M�ۏ�W��p�PT�.�3g@Em�;�	�$!{��B'" 
f 0A;�%� 5���b�����x�~$�K�eԫ��|{���Ƭ�� K8��8d=T�!)�����;�v�bL�ZT��f+�PZ�
���)�l��|ږ���sK[q��+���@�1���Y$�N�[|>q��`8���Z�R�K���Ը�G��`��\N�X�C�Ƃ��$�c�n�C��\C��܆&�Nd��aψZ��H�CY4{�Ґ��/�c�t�Ȩ�fE9�B�6�,�BZ�	�10�i��H�v��c��C��������+�?Җ���Y%.���"�� J��ǎ��8#D1�۳nm��^�����mncv�zC��
��ޖ�����D�]�u+�1{dr��;�J�̽��0���Ŀ,���(�%p�[0	�x�*)���U��"ϭ�����4������)�tlbaC��	�J}���L���i�,�$<i2�Ă|Rpg��ċ�N\G�7��R��f�2s(�wp^�����9]�d��[_��i�O���Hc�=�\_��]� 1��/�] l�b��As�pϰ�!��~�	g#��9:�`9�E��6и��TMc��L��0߈�f	��L9��C�9�E]X�� �&V|��ȳ�{`��i`�,LK��%݂� ��2��K}����V�T�`WO��|,R蝘���,�j��v>����j~�� �y,Y���x/,�|� ���������IȬ�$%���w^IV>��0K�����`ɕ�*�,pז�OHgE	
( �1h�U��4��)Ys��\��x�3D,
�O�87�@4�@4�@4�@4�@4�@4�@4�@4�@4��'��ß� �  