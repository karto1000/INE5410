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
� i�[ �9	T�ڸk�E���*rQ%		 
"�D�Q��8$C2������jE[[�um�ui���}�Kk��u���
��Z���B�(�ߝ��㳯������G&s�߾��H��&i�I���]�p����&4$��4AA!�ZMpH��+P�
�B!K����B^��,����=���Ӌsڟc3��x�n��������\�o�R�OP�ӣ�$���6�HH`o/��Xx��?n�n�l�Vg�I�!�HbuCS�"dZIL�Ȅ�Y��#khb Y�d�N3$B"�4���RT\�� j����f�$��!
Q4��Yr<��8���Hb�$iE2�2<ZY��G��wb�x�m$�+104)�r��1���3�4 "�&I��-[�G�GYH�� ���6�60�BP,�[�����J%�my��w0��Od!�m�~��S���VG�HI���̥`�����GT�rM�!����PI��@�����H*-��Hڞ��=!��b���{k���?�r�ɠ�X]V���^&<k%8�ґ��	'E�bmŲmD�!�#���3��p�?���&�$ل>��ar�F���#Y�H�!Y��e�������\&��6���8���^��7��7P&G1܀?I����ی$��34G��+P�E��'d��ɍ6�"J�	��t��~~~2M�D���3��AJC<�H��F8�S���ϼ6���h>�u	�<	�����L.w���("���>&,�gؓ,��)���{Q&��߮t@)0n�̒O��(�B�+�Hl�q���E�Dh$������b$���)�G��P�*�Y˳��}*ȕy7� 7`0ft7����&B�He�T!�]_;�C Կ�#��q��N�'�M�:�W1v�z.{�$	���	`��%��*"��AEVEs9(C�]��ɐ �R�T!D�T	�I�(�P�Xr�Ĥq�3r�2��"��n&`���;�]�dJ�g���@��诐��n�B"yrf�߸��P�Y�BXM�9%Y�R����ƿ��AA�{5����ڿ���q��?$VF!�([c�"lz�G�t�gJ NG�v	ņ0[	΄$�_*hA�;и�جd]�Ф��8\�p����m(N6|���6��	$��������4�Zf����,V��%ϻJ����%��Q��la����Le�L���(���2#^�@N��-�?�Q��&�ֳ'~�
9��x�#��tMf��.��}4}������$'�P` ¯�q*�4P7?T�U�hY��<�r,O-0S.���_��K࿈ԡ9� �pPp����8ŷJa ���&�7�b���l�H�@zܛy��g���h���%w0�	�l O7^�	��p[�#
k����5$zx����&�K���߈�Ra��2rH�S�[e�Q���0^B>�
�[�n3�J�!Z.���΢�v\�TRaC�"�3���X�UY>I�l��bP���b��\�Kvs�)D%&�H�G��l�}H=�������Dq�wU���U)lq(��[��
H�AX���C0Z3VlE�,����tj���|�*�qçT��i�#��y���ඨ(:jD\ֈđ�1:�)��~�v��Xn��Yƌ����8p��m�������1�b%j�!�8*�oDJTr
�K&

�GX͠=�>0	��4Ė 
�(�NE��xe�^�{�'/�-�'4n�����B����)k1t���"Rn,,�.�*
�:C�["< ��8p?=�Z9�CP�+�gl�x��	͹I��a��x7�lvRb�0����b�fT��<pC�pџ�B22�7+91t�N�����ehӛI��ŤS?li�΢�pn�h��'����EO�,��[O��Z�c��Qf+��)�m��ԓ��H<���1���0IcC`(p,d��4��ƟE&�"$=��&���-$X1O@,�C8�@>"@�&�Rx7�p��X �H��,�#1�K��Pa&bL$�)���������TH��"h�	a �A�^�����r���!���I[�؄u�ڳ-��l-�iP�X'����x/z�m.oT���]0M��$⬈G���*��G1��F)|i����4�g@9��T�TzJ����R�^���Ӡ{E���������%�5 OV�4WD0��03�=R�!�ۇ�(� s��"�Cx�~Tn��Ur;.�<�|�X��BaA��C�i�k���U�[�*,�a��^����P���Fl�ސ���8{�f*�N=I�4�	��� �����1Vx���]�������G<ؤsi&���?O:ܱ/��|��@'�����M�+B�A�gh�$��L�/&89P�Zl�����9�ٌϢp��x���!�:J �͸y*0�� ��7E-����E>�tC�G�f�HqJ@�"�T�@6�������B���o�����`�,�<�̃�fL�J��5,*&q��#/2T�PO���a��b���Y!;66�d���[s�Ѥ�sc�@G%��nHW`}�7��h.���4��f�ɹЃq���5�o�@��wa�	D��X�	N^]ɋ~�B�y`��䀦����{�J������<��� ��儉F`���݈�h]BL/y�.9+���]}��5|�@⹱�k!��F�I�s�w���̀:J�hP6E6
�&��
�Cx�2�bM�44ɓ�>����Z��Mα*u�W�q�T�oa�S��`7�N;���UjW޴�{h���e3cT<V�TŹ}͑��������yp^gn�,�ka8�	G�!� n�������;�O>�+��a�s��e�&L܅�p&#��LzH̒��	�p��.W���nk�v;,��'���c nnJE��t��S��,;��2Ǣ3��l� ��;��@��Db��82y5*��f�O����KL�Nb�s�?�9>8K<E�����^ԋ�{5�qs��s��\e�/��g{�^�/gZ�c��-��|E���]^�-�g�O+n������Eq';�{�����l[}ÇKxe�:�>���ڵYt���Dגͫ��|�Ȱ�K6������|�~��%�v��|wu��_���~�����Wg�o{��߼I��z����׳��<�՞����f������/��pn������wu^>�V=fť=;�'Ծ�ݚU��z����Cr���].}akjM��K���Zw~�5f�ͮ���wS�����{����%�֥-�|�4/o�u5s"�$�_9a{B��S��\�����ϭ8��ڐ�7B���o:l})B{'����`��ݙ���ݨ��e���ޱm�����ή<�0���.�蔙���������?|p�ؐ�n��W��׮�Qӹ��C}Bew�޻�~��W�����eu��oe�6�ݳ�*>�RSu���X�s���Z�P�����k�sK/�>2(T�����λJ�;53a��?�%V�k~%��g|z��;\~�zݽ�U�VMT���6wO��mn,?���|ł�*��d�g�k��c[��W�Ƚ���u�	�tm����~����B������AAr��֑�䏨��o�yv1�S� ������F�ݗ�/~��O�w������e����26�`QƬ��J��t��&�J�8��cb;=����6/�Gn�h�]�5qE�F_~X�㛑�_~P�c��Wk~���XsSsuN����$KOl�m4k����;̓���Ӕ��ޱ?m�4#���wr�E4����WN�\�b���q^��/%�j?�_zdMQz���%D�4k�f����.w���;��U׬_���ܾ���=s�,��M;�rnA�Y?��Ү�.h�u�Ԋ��''��m�=���)������VYU�v��f�VtY/)E����/;�O�?j� �<�_��x}^ҎM��wZ�X��m�KS�|�YY��ԛ���@3!u������R��;�R%�Z�-��}���� }[����1%o��X:�\�ς��.��H'���b�^���z�?_�k����G-6�N�`T��3&���S��G�������ǢD�-Ck�α�����3��芺Ȣ���U^*�1�v>�Oמ>����ѫ�7�������~Z���j�ɮ1��y#����SU���M[SYf���J�z����܏>��/���d�v}��&k:u\v~j���5����]���S�t�亏	���B�Do�>[~j���/.]:9Ԙ�u�+�����B̀}���q;/��'5>���m��x��}�f�=~{�@r��eV���`h��U����3�GEi��<�͘�˃���L��ԍ}�~ձ{�PK���_8���U�C7K���>����;++g��5�rW����\�N�-�/���m\trѯeާƼ���|����|��Qlc����5���?3'���XM�)9����f��[�~��������1�f�������'U�nY9�o��J�f�߾��B��qp�o6Ŭ������y�Y�4Ճ�蹈]���|�-��v��U7#-[�!�jkauΌ�[5���T��6�@ɾ+G�o�X�Ұ+���M�5�ҿ\��4��wZ�6.>1wK|���{^h�9��3�~8�y��C��޵����\+��_9���&��>�b{�~=Zm�p$.-of��&�g�vR��iW�!u����!����mF���MI�4J�r�d�ַ�ߊk7}jKbȀν:%�L_�7�����Fy�ӓ��v>�K��_-�]ٯ�+�����R[4�����������#���s�Vy[�Dn�쁽� ]х�^��ޗ��W�z�O��W�3�}�p��O��t����������,nW͒����+wWΫ��.�T��y���ɭ�*��Z�x*�{R��&��,�=���ՙg�?}�k�{Z��9��Oy���?�{�Ɛ���s��+�!>��K����*zM\�P��Ҧ��^�ͼ�peI�� �ZV�]�-�J�������:h��85�h�i3ZMɝL.wz��e��tz6��i�&���qۄW"���?���+@�p����	��Zwww�Kw)\�{�[p���;w��zw�z���]=�3�?��B��ُ�S��cʰu�Ga���]Vk��S1�S�GN��'5V���L	Gv��^E�]�V�;i��<�Y>�}4z��X����ֺ�9,,�x�6۰"מL(�?��`]0�dNܩ1!'#�#'��lE�2�S��KP���:���qc6�1�l��tվc�Ԅ�����G��@��n���@5����|�;E��0�m�09�弖��-�eŽZf�JE�)]޵EI�}ʆ�����-f{����;�� g	�d��o�Ɖ�\N�{�t�k��$�Ю���"yT��v#
�*�ɀI^"������b�%��Q�Q��/R_.8$'�i9�����t0U?����Au_�^�)�h�3D������nw�"� �jT����:[��}#n>F>�����q/�}��X#��T]��ќ;��A"��F�N��
`(�\�����Yb8�~�U��n�{v�w��2���𦗍aL-���Z����5ua~�nGFeV+Z��	G}ScG�MP�W�r���ة���8&
�݃�EOu�Eĩ㮈	f�$�1�5���g��,mĎ,�	W�Ra����<�ۣ[��r"tB1���Cvxb�pఅ���K��Nk}s>����~��9�첂S1�{�IE�z�X-�0����A����&>���"z&2|p�3�?]x�=�6U����9d	�?��T�l�K�.mpo՜�~,ݴ����@���|B�V��(T�!�����2yw���H�I0����E��s��>p�)xu����CL��|��S��z�*�}n�n�࿭w�s]y��s������N^�n�Ü~7^B�4g��{ۚ��sz�s���X�x���m��^�t���o��|�\w��:,(T5D����bQ!��'�j�w�1i,�pX>8��MZ���X��2�̽�R��@��Z�Qy�����ZF�J�*|�y+k��g�u;z�}+�OR�6�:p09�8���d���(J���,e���Ua�����?~���b�K�{p6�#���n��/b��̨!����-0�X>F�6�%Zz>��Z�>#��T9<�qRϗƉ�6���C���M3h~��>T�y��Á8��~9��dN$�8��^?�������VV�awV&	S�&�L3V~���t�gkѱ��}�����u�E��U���WȦ0�	b���2�M�в��~Fw�o�7)���	��oXr%�7���Q�a#�NDW��B�T�ۉ���M�f�9��������n�A�m���Np�;�[�-��[�8)�%��c�����	{��ޥ�%�N��֏37L�0�l�pr���j�i�F��Y�>�r�$���Z�����[���$��1.�v
S*�]*ف5���O֟����l�y�����0�����1�9 Z��%��7I�w���D゚�g1c��+	}�0�hR�)0ا����������c�Sc���
6{ή�T�	������D��F�X�
+��4�蟍�f��g�����<��
S���[�
.�WR�o�M����>�^�vkH����\l��$+�>S%D�	��LX�e���c�N#�ަ#���]��ͨ�Œ���M�G_/_%<��bף����� �E'���~��*�82G���(���:�w������_%�q�2)��d�ͫ�%��_@PT���?_b؆�LO���Vu�.mj3s�o��@_���y��-A9��o'y�����B��G[N1h�^��&��h���)b��<l���M����|�7VE��A�,~Tzl"*�}���'.nw�wK�@�PM\쮃��T�
2Bq�`u�A�)��8;AGbr�b0nh"�����Uq��rR��T����P�A��{�2�g��&�3����KQ�W����L�����W��_e�C���I���0n����sOĊ�*������/}2�0�oz(�~�z��{���H0pO�Vh���Y�����k腹�t�`U��Y�w5��W� '�$�κ$�{_=k�́xHZr6�P�&u�~��!�����v���h�y���ףZs���n�B�)�j��wUŞ5��'!N<�D����|�Z�kF�i>�A�a�%,��@��+�� ��#�Ww�_��l_�W�ʒX>�I��^������w��g� A�(�D�Q�}��3�Y�L�8�^�V�Cr���N������u��uʏ�+�]5�h���p��Ѫ��$S�OdA5�9�2��+���⌃�/�Ill-���͇��J�K�Cx�D�"��������T�(x6�-V_�0��ԏL�퉋��vf6GÊ�j~��w��r�d*��	�Z�nڅ�<wr��.X����6��`w��q��x��(��fO�]U3%f_�߫��BbD�4�F�~���k���*�̀s?�i� �=`�o-���x�U|~����@$�����-���B7r̲�5�3{�f�6mZ�k��d���;WC�;)L&��U2m��p��<{4,��-Ċmr��/+�)&)F���^(u�Ɛn��b*�Ş�|��r������l�+��@gVI��h�X/H��t�c,Hh�@�x�;�3��[���	�.n@��s�	(y#b�_.t���~�㉴%��n��̨k���Ts��|�hd�c;�xn�FVa���^s���{D�R���0�i�gt=���n��YKՆT�G7�o��;艾���*��MA;ϑRΠ *�́����^r�A\��į��O�0�"�t�q�F|/�N�-��ΰ��c�Cߧ+��
�XQ�|'6�vD͚;��T{�Q5#�Ui��µ�P�1S�z�c�7퓆S�'5�(�����e��pɾ�
{�^[���؉������k	�*���%��$��#@�T��8�Q�O� �������ьx��1�7��Nk��,��,ed��@� ����;Gy���B�0��p�c��p�s�����4-K�|��e�3�6c'���bF�>x����H���
�5�G',��7#0?/Qt���~���t!�p�J��yp� {�d�x�3E�<	��w����E��hS]��8u��+
����L��m1|V����m�_lUu�8&��1uU`G�D���Ud�?��!�� '+5T��p�U��kWt���]�"2��L�/-	��Ĺ�󢑈S-�� 6T94Y�ճ�Ж|��m�I�9�ڨ��P/�{y,��(�x�;_x��F��BX�Wla�i��wf�h'�����ڃ=�p�P����0�KmZ�e�x��J�,�5d`�ׯ�sd�1Rә�M�,}���������Kgc+��?�Y��$5��UJ������}Y'J�J0��v��F����ӊ����ja�v����;C�~�r����v�٘��c����Od�h����QrKnk�Q��I�ʍ�-�+�0:Ϝ ����IJ3D��<��'-��;�xV�C��pv~������T�t)h������썫ơ�(Fd`kX/d~�)���ܬ����Y}��'5D���u��+�����S�Aj�Q)u�V�I0yVU�!�<�-��ƬL��Iji=��|H��G0˂�<'����p��&��*3zrDu�a6��U�|D1���_q6��7�2>!�SR�;���������ȷ���:�K��O�	�:��"�Ǔ���[)���\���[��'�9�,$�XxǍ��'s��a��>whp&�[E��̫�tG4�0�*^���x�\�����U�`���ɛ��_���M�@TmD����p'�xPf���J�F�ӭ���*�Cӈ%�W�Jz��O���E/�9Y�XB;
���y�#��|$6'���XȊ��@bW��p"���B�v�Ǔ�D�'xuU�����S����V[hK���)H+��z���1�Z���zC�`���� W�S�	����?�I-�b�H�����5�F��I�u��=#�%ϙx܂ȸ_,�l�9�����7�� ^V�L�;��������qZ��� ��S��_�@^���{�
��{�-�%��`���*�~"O����<%�]e�2�3�"�i��N�}�~H�b�=���n>�sˀ\��,g�L�!�IC:���&�)�p�7�Tޡ$׳9ב�s%"]�~�~S���]y���o� �]���������˿��>q��B�W�\T
_[Ҵ����~O����2Ֆʳ�t��z����`�"4|p=�~����K��A}�!��d�e��7�	�D�~X��.����������;a��X �xyp��)��r��
���5+U��å"��6/��fϸ���D{�Ui�[Q��p����LBgS,Y��M[i�c��)�+��\Y>Eݿ8Τs���{���YƩ������~}$�X1��`ܒ��x*��E|�W���k&Ǯ0��d�?m�\
������\��[�HO�׼�3m��.֦��Z��P�Ћ�ԅlr�}
m��đ&�{>��(�Z�l�Ǟ���?p�(vpk��.��0����.�ha��jRk�>Q���p�q��dm�$�ϵ׈M�E�sfu\���
�kzb�O��6�=j�Vl&�=�����W#��Z����$	������'�#Q�s���nz� }A�gR�H�����'�||���6����CB��\3H�Tߞ��k.��[�A�\�����6Ҁ�4_����b=E��i���r��;SHk�f�;��uY�^Ї���%zW�f�H��`e��^0��!d�ê�:Ȑ��d"����9��$�\z�U��B��ҿ<�^��m�KLۍ�7yF^bg�R���^dF�$�.�X�lC:� �q��s���CR��|��Ǎ��\�ƷE����]VoҰ%��i&�_�6�����ݣ�xm��z�����|�(�����m�S3�&>�I��&f�S�@L'�H��O�+�8���OWHجŕ�ё�O�D��\�{#+b�i�2%Y��1E�\XC֊u�`��lr8�8�զ�ϓ_��݆�=�{���̳�r��6(U���6/��T	C�g^A��jkj�;�d�i,m�\���ݍ�N]U�6���f�XN�b� r9�'�'8��h�X`|@�z�Uw��':<^;�U%��C�f,�1��1��/��z}'s_$1�̇
���G�2�8��ۧWQZ��Y��U�f̔h����D���'ҺD�~��X8/�Q������|��v ��_��۽,OA�:�M%u��+�,�ϖc����C��]�y�>����(��ב��t�ܾy �zSu7��O��\Z������k����'q/�x�o����W�Ѳ�K#-�s��ˋ Y�֪
����Z�Zp��L�=6q�OR���p��[�f$@�
�^��r��@��l{�::4B�7VvŃ��*���7�f2u��p��V��az~��H�	?�w��~�rk�ﬤ�e��&�F��럈��$x�@Q�~�Z�<�pXʣOcCt�ӽ5�i��T2<�b���x8����H�"ʼk_DUq�
�t�J��^��r#�|V�=4�_h*1��ћ+���>�2��I�,�R��EK(���xL:]�gE$�y��Rm���q��O������LC���ᮋI�Z�U`D��_K'��WN��G{�潌)�s�-'��Y���{���������!_lIZ}�g�)l��~���
�}��3@9U���jvM朁�~.ۿ$��V����j�!�����ː\̜K`�}�%Y�C�Q�o3L��ZѹP�.͠����%wޟ���K׳8���DE}��v��Ts�$Ru�q^�gd��'��V&?����cͮ�Yx�>o�td�jS�hL���5�D���㣊"�LhB�u� m�Y�b��>P�CA�$d�Q�¨*.��z���v�]q���*�(T������,P��{������zQ7p�Ddg�4�r�fcj�5g���:�;A�N��{�|h�Y\��&� �=nά�28,n�������y1UZ��)���/��9��9����<�SQ�����4_/q!�a�_6\7�ݾd*rjGs_��V}�A��tӘ�M�긛e?��鼨�pAq���0����$	D�m�T����Ss.N*|?�^V f��}������G�9T責�J��Х��I����X_���:J]1w-:���y��DF��N-J4Go�s���-���4\==�ݭ��p�]WtP���c��!�q�T�XV��j��E�������?.��>���_�c�df�1P�?��T|r�'~W����� E[_$��`��6�u�^���T�K4����6([t8D�<�&�4��q(:�
����bY�%�8�'������I�A/��ݘ�ב�W:���]&�V�Y�[~� l@!*7M�=?���=5�K���⍜u
U�͵"X�-�ˑ�1h`n�`䘔-���:�M�Zh�H�6<���?�en�<%ΊjB�W�2z��L4^�w�ih������.���TV>���ﲘ��z��w�w�b%��1%���^_|��j���s�n=����-������`	_��.q�k*ɐ�h)V.@kIl����1�k�u%��|��K�g�{̚<b�Ta�����,u,�%�k��Ҍ�7�N��>�{�Ȓ��3uk�';�D���+�3B�ky��-9Rl�1D��ihd9�� � Q�×ktb]�%'�ne��'!-7d�b:�C�Ⱦd����ڔ��ְ���d������#J3��v�����Q�C���`�?�,9۔�S85�mg	�d#t���{+<h$����`�<ƅd��b�rY���ŋ�
�K�	4ѱ�'�Q'h`�� �w�{ڳ)�@=�/jJ��N3���#K</��Y��O^z���*b���I?�rc��U�Zi}Y�931m'���x���>�}�WGn�9���l�s��t ��P�g6[�/J��^9��]�<v�_���� �A��v���:�{v������3f�q5����� ���b���D��a�������O���������_����?���P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	��P�	���_�τ}�G�ZM�VE����t��';��<�(jޥ}%�f�4z�7N?��>Q���gK~�N Ӹ�&�$6���������'�_��Oz��D����R;��� ��a�]�6�e��<9Fܢ�b8y�:�F����d�-�o�}}���	E�����j���u�n��f�������A��RA<wM��e�s����x�H�~����,���c�Z;��D�Ė79,���* ��/%`tn����V�t���J0�$(KF�w�= �f`X?m��a�k���L�)ԷU��I֎�4����P�!^�0C�a�%�G�zD��/�[wE���ݨ�!L�ܤ�l���TG��A;i5���1�X�&7�&_�Lf`J= 	��z'#�($���e�u���w"-�� �+�(þ�aEc+7�L'�J�-�e��8�PO�B�$x��A����J�F��!�;1�Uy�D��\�?g:���g��t�{m�ad2��8��5G��GB��`UE�C\C�H꡵��\�kr��^��3�嚑��a�u7�/^>�E��)��7���Ƴ��� �msNp��p���������.��H��Q��φ�f�g�%m�?�X~�$@����Z3��U���5�q�u���������rF��v��� o^t	2M}cj�	�Nc\[�L�
�D}�(6p�	��[@�l����m�S��JX�e�sn����a~�Ft�R&��<sR�K�����/׃��i�E�R��m0L;�-IY���A���_�lc�{׾EU��z8/�\5�V�0���}��e_����~�M&�)A��o�p��#����D��/�Iڒ�;h����s㓙��`ŏ�?��e��|K��f'bFCd�;�p��%����E�w���c~&Mo0r����AW��w._���#ۊ�M�H�VQJP*�՗0pW�P<�w�k|�;���\\�Y��4�'��s
[q���O���c+�[o��?%;�p�������k'�d��L��\����P(S>�'�C��;ϰ��.�SDLh^�Jh�B(���*(M���P.%�4��.EAQA��E@�4�4����(*�y;�̇��9�'笳��{����K��w���zmP"O�̼K�b,����>�+OE	U�n�B#�q8UA�<J���a-��*�j3UTw�j9���S�}��|�����^+Į��+�7O��*�E�#�r��k�,�ƔS�Yu�Gw����kW6g,9���y�F8{�%b���WʀLs4��H�Qch���Kd��÷%�B�^��y�łR�V��'/����s�� !$�4(�kxCw���
BSqMц��S�E�Q�p��]n9�&�L�M�a�a �f���#F���x�D:M=�e�7�J��K��4g�K���J��l�`����.�d<�4u����H�Xv�}�Ul�+q�}kF=W�&�s;�c��%�@Ĭ^�o�yu�5�a�U��4�x;Y6��n��.���5�/-�ql���N~z��4�����tW%��?9�ey�eK<emN����w,�j�ǝ�� �Gd+း�t01���xW��E��y�9�7�\��Ny�l'W�� ��y����٩w�29S���� r�Ln��%j���׆хw�$:�LՈ/z8�3���Vk�.��F��NI�3���o�-���0E�W�5�s����Rڝ.�̑�0o��;o1�ts^BV�ZӾG~��0���9&���	�'
cZ��u}�6��ƗwG&��IE�Z_�ʘ��<�I�V�Ğ�q��޺//Q���i#�:�OQ��x��M�S�6,gyj�gbsn�/��f���?�1U��*F�_�n�ZR���)jn�z�i�E��1wCw���r�Erdf�[x �pY .ִB�4,R��{xU>Q"-�׶�]vX/~�q]�MK�-��@F;6h�2K���Bm�/C4)U'�"�� q��Մ�*|r���P�4�&RUygkx6\����@�빒����z7CIw@YT�-V�ö��)�jW��E�S-Z�fR��<�!ͥU�O�=�e��]���-����p��r�K�}QN������N�c�=��]�0z)��|��{�r�\��F���1��;&���,��`��q��������-����a�_�o�Wuh��y�g1YYQRG���f����+r �����#�i�qJ�)�'U��������ǃ
��e��rӯ%�SDWz4��}л���T��&�$q�Ix��n�b�>^��w�7TA�[!ńnW�Б � oW��92��;x?W�%�_��+ӌ؎�IM�-��
�'��aj"?]�����ō���]g:�͌�x}��d���nj&��>}}�N��~��*�����9Q�Y�[�g�;���yr��ET���3'vjD9X����^z�&�����$.L�`bZ�KS�{,�����^��v0���R3�V�3�����Ǟ@�����Yli09�	?q&�*,��i+ž�'N�Ϩ��;�4�����!�ī9!����Q�I�x1�VK�)����^���#��}O��)���j<� ��U��"��8�K>��N�i�Y�B��xe�AHa=vܟ��HZ|pT��_z{m���t�m�L�ӥ����J���W���Sf.I�JHܕ��I;�m�g��L$���� ͠���ji"����Ì�q8�jڽ��y��!�r?/�3��M�ɸ�ӤO����+CnL&*h����9����Z$��1Br�&����m^UD�.G���˛<���2�������THD��kr"���ҹ��a�#;�˔�8��p��ɴ���2+M�D���`ӯ�>!�5=-!kE��vL�0���y�+#��#)VO�B8�%0�J�`�=��p�b���&��-:d��7׏k��u�� Ea��S>����5���wr��9V)E�G��p����f7γ�[b������ܰSt׵������(���$8J�9G�L�M��Ѱ�ptR����eŊv�������"F�����VJ��y�,0��Y{H���I��v����;�FuR����u�N@��=im~Wώ��J�c��[O�MdEr��+�)R:m�:^��>-�x���z�WF����r�6Z�k��-qއu�fo�'k��@������@
A~�a1��L2���y�V��q�ta��tV�Ǝ�\�����C���_���^�~��y���N��Qx�\���R[S���e��b�	���;�q��M��j<`|��3��s��wq��c��8{K#C遍c�p���=�|����9D����j�ܮ�P�~��	�=����.)T��N�r���]��|v�������a�7�\����ЅGm��E�����M*o�>\�$<���;,�ɤ=�k �E��I�d����8Y[�oNL���EDC�D2d�
ۊ��w�/{�*M.��� ��"�D�֤GEe�Q]-�zrV�-ŧ!o��`�����X�Rq���e�k2+�xߝ
���ߣ׌!WO%3�R��$y��2�xg����>x�ϮFG�����դ���IN0�Jsk�>�w�G����^���OJ$
�ؐQ�̒�����EM�طd<���d��bZ݉8�6��-*�4�  ���٬F�����v%��z�DANY�P0��J��P�.����d��íN"��z�-o��_�w������Z����I��/ �����vT�o� A G4�u�\�
������.qX<�e��n������Pe��N5<P��\�hԗ*b�8�'��ay��{���"EW'�I�8�(�?��Q K���3F��Q0�AU���x�D����G����C�@�W��a�9�/"��]g����f6�g��������5]�O단�7����F����!
_9��|��G��5����x�h���#�x!(��ʌĂ5����H�>�r�za�r ���F�&��*�א�F�hV|�`V|����?f�!+�?��Ǭ�\�Ґ�b��k�n��D�;�#��_��O��
�6ݏ�SG~s��H���/��@�����]�_]������f�4Dܮ���}T-�g��}��,s���������/�����y�o6��	�v�����v�~���nw;�v�h���s(�o����[����G��n�9mX��	���of�k��^�n4����=l��@?���O�߾�u�};w��}�f���ٟg����f�7c���g:�N��'�!Ⱥ�!���P<������������������w����?a�O�����?a�O�����?a�O�����?a�O�����?a�O�����?a�O�����?a�O�����?a�O�����?a�O�����?a�O�����?a�O�������T:��ũ��^~.QR�6%����ݲ|x"�@��r��|�w�~����8Ս��ݜ�f��U� �f$��DL*&�ݩ��>�w��ڵi(���uݪwh�N���M�e<}e��@9d��[���	�H`��;����K���@��Pe�ַ�\w��bev��ϧ�6�������R��:wʰ��Vr�by�a�.IxQ���|S+;�|��u�����7oy�`o�K\[����4��Mw�*B	��4D!Y'L?��,F�-��ͥV}6qj&-�= q�*Pg;���c ��U�T[���׫4��jzIt
��^8�H�0(��s�U�a�} �� ���%����u�堵�)zO�P���w9����=�d�M��%�FoI�=��	✯ůO��ϗmy�,ү�ey�y�m����n!��Z�x��RaA;
a��Gr��k4g����!��y\|y�v������Q;r���_9�m���"��,�����ck�`
c�u0�������g��Ȏ,w���GĄ�Pdi]L+�z�q�7���L|)kōW]qWd\2�S��b'Uw�Ʃ�*�c/:K��R�l��VB�`:@R���B���K	!�"S��S�="�lX!c���Są�gz���ع�}�|v+��:V�(� �C��0�v:��=�^�}�{�ca鎻��K�h��w;��^?q� ��(�C�0�F�>X����S
��� �l���T甐������p}%&�ɫ*}���#\� ���oH��7'k��w��OBcB�C�ʼg�@Y�-�m���9��>�'����قw��=Z�4�TOF��`Q�W��/6�o�2���E����}��q�G��G#N=d���ޥ���\�LȨOo!9[C9��s����)&$��.��� }���O�ò��5D��V��H�9J@Z3����k���V:����{���1f�^o���{N��A:^+y,(K�(X�^��cԖ�ٮk�ZJtl���ζ����{{�KŷR���/�H+�DW�|�0k�5�i�x8=�����nK}̚ǻ���}ЋN.����ǀ�%�E��Ѿ�v��( �}R��ִQikJj���.Ң��D��0L�ؕj�7SZ-j�Ծo�R4�Xj*�D���9F����9����/�F���}�W/~U���'���Y�MąW�>��,K�]��1�2�Ǣ�ƃX�N)����)VߋMNcO+]����f�?�Ӈ�Ŀd���N:�͕��c"Q�%���~RI�(5eJ�z�;u�dZ.ue�C��̤q�A7�
�_G6�?�����O�ĥn͗�����Wr����A�m*?8c�ܘ�0�t\��Nx�U�F[����.���\��Ӣ�b���.�i�WzQ��d�U.�f�˵���H	S	�����?��1�-�G)-��u��m�7Wo������KO����3)��(M�9Jߓz<y���gm/����.d�H�+�)q�k��Y'��?�z�3|#E��½�p��C_'�"ͬk�-^��j�Yնҟ2s+����xF�́�����ȏ%����D��0��4}/O6�[Jյ��������)�iU�^�O���zj1x��հ��̏s7JU�ԺSW]��&�a(z����Wb��c�F(iiv���c���
_%��Gl��ٷП�PB\ŏ�>��ҡw��$��"��&��粭�B�9	�[�0�YA�]��ۣ���Q�5p(�L��S�G���gn���}���,�� g��|{	�g���b��VZ���F`A)���Ji�%�Ź�T�m���y�l����<�5��<&�7&R%���	��;$�x��<Sg�h��k�|<���{���j��_�ճ�ꌝ���a���4�G�w�%Fu��[����-F��v}g.[`F!�>қ���h��{��X�TF{��T���<�j�Bh?y&?Z˷4�׆��k��C�0�S�D(B�����⇁Qdɻ�)[�}RD����B�た[�e^X��a�	\&�_)���8=:�KJAx��)9��O���[���ʒ��p�������`�)���m�@KƐ܊۩g����j�r�'Y�
�^��Bg�����P��"�/Y(�)�Ԑ� Ax҃��S�U�^���u�zj7�5J�E��S!%���5���g��=�@4ݽ�R�AL�����[�t��$Y�"��e)m���@Tf��a�6t�#u�"�4��	�6=���]��=56���Z�B�H��ϟr�����vd����P&�Ƥ]̳�'׀Ɉ�{q�
�s!��h�Oq��~eɑ���U�}��h��v��Ž�0*?e���X�v��Kʾ	��� �}��rt����ߐ������5�d#��Ȝ���[t�eL��aKa�������橧� M���Q��:toC��p�=va˔�ʪt�O?>�8�N�Ap�	Vs�D�U��-���.����T� ���o�Kn�!��p��8�Q�w]숢���[�*o��H5�Q��5�.jT*��#dn6��|M6H�{^��IÔ�kS�w ��'�D�G'�2�1�(�����.�d{���:k�f�x���f�o��S�=�D{���O��O���iQ�J�,o��G��i�	"��̹q�"�aR��f�tst\�����>'P˶�=1�J�6���]��=ͦZ�ߗ�{O�c�7;�6�I�hp�2"�!J�����������S1yz��Y�2���{�Ni���q��8(=��_��                            �'�� �  