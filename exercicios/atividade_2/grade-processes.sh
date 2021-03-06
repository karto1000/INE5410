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
� _z}[ �:y|պ���\EDN�iIJ��T
)-m�eiK�҆i2i�&3afҖ�,WY|�z�
r},U�U�)�Nq��QP/
j�+��{�l�����������ə�|�����I�/#i���=f��$'����d�����Xl6[�5%�bK�1[�I���۱~BO� �~����������?�0~�7��_����?��wyZ�9KxHCA��G���OIi����Vk0��~���k*�hS�����,�Ƃe9�e�5V,3�8�Ȯ��׸���vM6�����9֮IƐ� p�<���:���<d������a(h�9h��a��` p~��@�r� B~@���-cI��04�Q^�� ���H""�>���5n�$���$����$K��� 2!7c4q�,*���2íXn�i ��!�e֋D�c�VO��@�U- VPp�a��,!�U.���x`A2Q�� &̘�����4H��d��������������.�����YW^q
�������PP��AI_OqE��� ��`����'�a��T8�词�K��2�]q=L*n̍ /�r2h�"�.!�	?X��y"�,dX�bhHoj�7%0n�䎒�A�0o�v��I��fh��y�ՁZ6�1:'�5ήі�0�>l������8�%�"X�˻!3/� �'����E[���^	�yY������,�OP~8X��ʰ�-:�L�5SKSKS�b@�Ā@I�g�]DeL走� C�n�ϑm�QJ\q�0� �[� 61;��n�����p2�5��q4ء�ja��V��(kk(���`[0��
��C=��D�\C�:\W�V�A ���J\A12��\$�C}	*F��2!A�$	��"��#�UU���!�6�R4�N<�h�:q=(��u����5i�[�"��[Lz � 7�NNBD']]��<��D��_ @��Adę�F��d*��AZD����#��	��J�Oy�4r�v��F�O��i����������G���`4�r,�kP�|1=\���G`��L�l|�@>jH���1�Ds��Ӣ C�
I�q5�"�7D���n���ís�,ό�t��dݔ�b\�ت��?�61�����â�Y̫�ϲ���2�%�<:A�(��se��Ve�G�C\�P�A��a-tc�5���8�3��t����d��+�6�J��A$��	� �j�0'���u��F2e�`�ڎLYS�H�lL�ڑ)[$S��C�"���CUR�<ib-�W-�!� ����O��f���&���Am2h����*`+�#�.�(�];�-f�k�	������\.eJyZ8偮� :����2ECP�P �4I]]�A���R!�S0!��YqFD��EE p\'iDW'�^�"��������u2�j��@��:!.�$�ɉf����@+퐮��7�3�:Q�NA��JQ��=hm7`S� S̥�),6յ2�� �2IU-M��K�I�*�Rۖ2��A讋@2)Xț���]���u�<`&�K6 �z Pˁ� �H�r`j=P���0U�C�x&�m\� /C��$k@���]�?��fmׯ�-�6Kr�����g��{<��?H�11�{(�Ű.�u��JL[p%B�Js!��5��`���m,;#�U����Q��:Q�� �\�`���f�રh��B�$9�o�^/4Ӳ�H&>4�����-q����0�9��ʌ���9�i9�Rt9��(�G���ܭG�61��y�$��S-%äy��z�e�U������� ��ä[D���"�F��Y��-�xN��q�H�\�&�J�?+�=�*B*+F���%�t2<'��ފ(%�f��M��H;r�Edc&�zn7��F٩軇J�)T1-��t44�t���srG�s�v�G,Ωm'sb�k��Bh��:�������M	�_¿�y`E!������1�#HA� I�g�UU7^
�8�`�čNf)�f<�W��q �c��	�q�(�AnJ{��H��W"r$J{�tBBǊT��Q�D�oc�өt��TtSI�8\"+X��0�aC8���� �E���q\��*���7��UVjZj�еH4@m�ڑ�ٮ¼�Lt�Y8@��=d7X偓���2��#q�Pk�rŹY*�cEَ|tM	QBb�L-�䵨@|�EE�/�R�	퉠jOY��'i��AHQ*����e����TZ/�]���8w�j��:�Өu��P�:-�lN�n�������ZW]���4&������"w�!�
�ųp!�APŰ�.�؜g.��Ig@� �φH,P����ʮń��1`t�[��'r�Ês���
��[�a�]�@pU���'	2/��e�W���bB#����2�(y&=��&-�%F$�p�q�G�����mY�Mz`-GbB.���<0�7ih#4,��hZ���f|L@0n�ag�P�0���L�^R�,�񈀪��(�V#�� 8��jt%���;�F��#�(�
Wf� �ޒ�
,��N3m��c �:�{աIu���!����A�A�PA:�Bet��Z˰��g
�PR�q^�A``Uo���l.��h|�tW��2��=6�[_Ef2,K�S�C�P 4�)7�3#DU2��6�<Q�P�(����W@��`�
���
2֖��O�kf�tV=��2pK+QV���"Er��pQEe,��D��rCԒ�h8���fk,H��5"d5��_�
�%��Wu+���TH:���=�A�(�#K�r�'��B�ݙ��u�T�F��=y�eP��Y��k�B{�pܑ"T��b�U��b��f��p����urf��a��$�%aJ*#�+���x��$,��?���B����Pg:"j�������Q�Z��</`�Q�\%��aⁱ�Ҥ@@�	R�`�M�b�����PfQ�;� ˅�U�^8a�5�2����je����*x���0)�
��F�a��T��gY��x��e� ,{��A�4�P�J</�|�h�{#�Sуg^���n�w�»x�0�V�:A~�«��d|*��W ����rQo!�hRAs����S��S�"�ސ�u!|4 �J]�"Ga�HGnf�k|F�XG��5ҕJ���'·': }��z-CT�)���.���&���# ]ҰLy:<P�CۣQy��	`m�l09F;���u�,.�FB/נ��#� ���݂���i��y`MK�H��ʴ�)�]S��,�G|���O���K��p�jV,�gA�\*
Ib�@����ɳת!$��^������L-M��"D\E]l(��rU@Ē�[��Ɏ�Z�&(�����Zq�\&Li5��������T��/�JWV�Je��b�i�]��IB �h��,�L�v���1�O[���2C*<�);�,O�o�iL�cѼ��K��f�Ԙ�g'�(�h��������A�cK����n����1�{���?��Ѱ����+!v��Rϓ��Mqߨ��?fb��*w�����g�(?ګ���o=�;�{FN�x��C�'_*O�*
&sG�W��w��z�xռ?�p�=���{=Qj�����}߼>kޕ%����ڬ�_�vNý��6/{����=kO��^�ೖ@��#��s6����f���O�y����S]�7-����֪����&���g�}yx��s�)�{��yޕ�&.M^9����3e��n���ϯ7vOI1��j/<}��W��wu�n�bFe�[5M��d�jgǞivs=Yw����/�v:&�d�����z�sJ���^�v���]��_�����Ԣ�=�1��q���/>�i��F��I���lX��s��/�v��Z�9����q_;����ud��Qͷ�����4�����_�����ů-�(���&_Ӽ�C��;�@��ߣ����':��4=��9�����%�W���?�%d߷��gV%=6cдٯ����W���G?6�Nz�s��sg��8�!�M��3���?�0Ƽ��d��[uo����7���r�<"^`g��[7���E,y����/�ո������ڸ�rk�C|��)��;�7��;t*#k^�qq�tӊ��x�ǦQ�������r�ȑ#�w�Gl=����'_Z����j�\�p��e���7�]x�����I���:n���t9�pr��g���g����๟.;w9���������oӋv���+����߇O�ݒߔ��u1��J�nx4���G��p�!q'>x���-�������w~�e�Y��}��K�G�Ϩ����?m��W�LS����a/>У����c��Æ�C�Z�W�.������&yv�xtӺ�Fj[���Wo�ug����uX�u��7���Ȇ����j,{N��M�|��g�굆�eM{^?U2�]��}Z�VQ^�2����:��]�� 2ǂG��?!�0�ޝ�K��-�&jȟ缽���뉙�5�gN�Wxy��翞z��)'={��v�{�%=�4h�.�t~�o��o;xF{��Ϸ]��}uC�]���v_�Xx|n^f�%+K؜e{��$��`��P�ՙ1��g����;>��������Nu���`�"��O��7Ow�uK.���wh����-y91���|�bOp�eb���w�m�)�����H��C������u�k�ݼc�|��j���Z�m����qm�M��wݷ�������#c��[ae��=z���Co��n�ξ��v��]��$�3x���*�@�\�鬷J?��+^���{�'{]0�s�L�X�e�澃7��?M{w�3����!����\v�;<��^$��{<?��T�3;7˾�kx�5�#��V�g܈����ǖj�m���*��±|�~�#�����\�2�d�;��߷୿�m��=K�W��>t[�'y�6�%榎���-�.��?h�����j���Cw5�?�}ΰ��g��~���Ew֌�|��Һ�z��[v|������:����Ko�0e�>��^3�� ���¦�㢱����.��ԫ�~QN��?���]�>#����u�_��|_�_1�'z�}q���ov��+
@�0H(1HJ�H��(2�t�t��t)1��t��4
#)��PC	��0RCǜ{׺o���{�9�5��������w����ܗ��6�*",w�mJd�-�V��z���ue��u޾H�y�`����"�u��07	&�K��.�1o�_���s���'/�d�$��B�.�;SjN��h#Q�B��)Y
�q�K`�3��IC�1ڱ.Z4	�UaI!�f��T��h���a�$��nāG�Z��ړ�0���6�	��Ӕ�_���v�f����Ab�� i���;��_�����x���/�����_�����x���/�����_������_Ss��'��L;Kh~����'��p��a}N��0��� R��� ��w\�e����u�x:����i�#%w�s���e����ϥ��6���;�XTUt����F�akC���̉�n���"�[� /��r���9+ .®��/e�<&.p�qW�L�=�INq�\�8���Ɗ�!�W�J��k��:�]M5�.B�׾�v���5��Z����%� ��.��w���W�֬�%�$]]��	���y�#�ע9�pu���
�
�^>t4�l�t^��j� ��D�/���]8�|lw%Ww@Ĵ4T���s��4�Q[���H��d�J7�������=�}E� Zqas�)#�g#%Z������{*@ϖMoG\	u�%p�͑�_�%X��5 i,LG��e�Q�o��	�"��k�u)��w����ܬ�0���'>ʑ�����j�tܗ�U�atC��[��/V�W�V��|�'Y��D9�L�;E�uC��O���?���d��i�Վ^$t�'����!3�{;���D�.�e��+_����A��ǩp2��$�HQP�)5bD-�#n1�~�S������\4�|+Mu�P*	%.�Lr�l�f+�`mI0��k�0qǶ��gfҗv���1��t�XVEn�/�(��l���M.m�(�k)>����=����)�	��v�̑G�{���J�x�A�%����"�����̈́�?�gk���d�f ���%��<{��_�~�
�!�];�kWK�� �+y�[��{�]����{�4�r���A{�#�dNs�@��F%�S�K�+Sݙ��ƚ%Vyy�5�2��"�waigT|g�>8�K���rƏ���04s��*��U�ݽ��U����������x�,ӏ,�9��7?���-�추{������"��l�����T[��'�"�c�c{F�j�����a���r�Zt���w�'8�����0g��r�J1o�2�/1���9��Q.O�m��8R3���ɽ���vSo���bu�g����tu�f� 𚹑����� �=7�ơh�ڻ�&U�$�178�L�⺏��m��$���f?pK޸�Xl�C��'Icj~2#��/{�MH�m���04����4��k�3�ѩ�O��An|��|:)o䈙Y~��"���sJ,�L�9��偋$�B�����__Y$���5�J�޺�~i-�!�QD�{�La3W�+Gr)K/w�Xw���L҆���[r�~��� KK"��������������RƴTa%�R ��1��^�"���������&`�X��O�����D�?������&��j�nE}��pF=?@AR	T%���ǹ��Ͱ����j�I�l�j`As�
�H�`|�^�EP��2�퉱��a:t4JHk�:��!���4X/ X/�W���z����ix�[����eS}��9 �^��.�g(�ZQN�X�d��fj�S�uIY�jw�_n�:�H�ֿ��OT]�WJ:J��7�O�g�؛� xӷ����:P���D߽�n{�Ѳd�$�8c�Q�m����J��vUi'9UN�?ݧ��kZ�k��!��C�@YR: @4���kWw�ՀH"T�r_�#�R��gU��ߣ,z~31�)���2�$�%_�P�Lt~߻�o��2e�:�\��o���������j�z�i���u��q�~��tT�t�˗��������hV
�K	#|{O��!E�ϧǜ_pF���bz}M�4)�f�;v��h�_aΧI��c_E���g��L�����z�JƤ 7��1���@w�������[%"�e��k���7Tx���ے��;y�Kzu��D���k祵R�:8\��e6�g�4��4 L��K�3�O#���R����F�b"����$���}h(��g̼��yy���U�򮟖o̺�|�����g�:�ޞ*s"<���Wz|��@�8g�{��Ҟ�)�z�X)2�$6�Z	J��<�ѿ�
�Y�����V9�W������	#��?�br�������G*�-[��,��H1��Wp��~��hx�����_~�d�=m����D8�m�,�J��5��)f������L�u!��^��[��2I���LΦ�l�Mԥ͓����x��-���1���w	�+�����8m��`�o~��c�V�w�#E�Z$�����ʐ��X�!�;lN �N�b&ҷa�/T�y�N:��H����Q2�*C�>F����蹩��^w(0��[;��b.�%7^&���ȍ���%U�T�*đ� Y����OsT�C�T[��4o�U���6���zO(�Uߜ��LQ�������
=�N�R���7(S�{�����I�	�����ׇ3�c�������?�?��ӿ%x���?������������x���?������������x���?�������������>��^R͆D&�[LCИWg�#�[��'�wm�������&'��桄�l�/�P��f;����؃�,�+�_y�o�����?=�aӷZ�|�7��n,4��$��*T^ݞ� 6�@���µ�b�:N?���tx&���MC��Wp�.r��)�`�6� 9��N㼤��[2�6�T=����3�QĤ�",��D�}����Z�ug�r��<_5�t��_i	����P�S�2���ȡ�[���0 aC`�G{]]�>�LN�7-*=�&	�$�29��6�����z����i �G.���e�1�!W���O⡛�����u�(0�L�h\_IR�h���.�e�[��=��\KdXM�@�vr�r������1�_2�>[2�Z����P�)�V	](45W�:���T�fG֓��p�
s�N���^�0^�$�Jg� �M+vٴ���s����Y�N�L�݈�ץ�LyoD�hK>'����~r����B��a�������E���Y�_ �{����5�Gw(I��b�	�,GüC�>�����>m�GJ��
źP?� �H�q\=�l�5�Ĵ���i�@9������-�Z�6A���ҝ�V��۲߬�V	�T����E3�@�lD��'=,��찙�E�D�n�o��t=�a�hE���L��;
���I�?C��r��A��|����2�T'J��z<+z��g�v��Ve�j[�����d�l�R�s��c[݄�bL�, 4�Н�L�7���imDW2bs���#�l�-6s���>�uecN6D7�R��3�܆���+S�׳�hr�b�?f�SE�S� ��Eq:��SX�*��DF�\B�
�7��$��K#�AV�����A���L]��4�j���>��P�)3�S!��%�.?W�N���i}4Ƿ�8�Q����eW�O5[ZÝ��^z��	U�f�	�L��nĹyy�%&��΅��ӈH\`�>f������Q�G���X����:�.{p��U�5,���E�3/���o ?#V�����ۺW.��"�
�P�9s��R��'ݳ*I���pE�mh��tR;ה������,`A^I����bI_u�RJ� �����+1�^�'���Y��Ք%�Lo�2�'?I��\��uU�Uq�Y6�����r�~y�T�����6����c��q^��=w�1�k.)ka	�氨��Fkj*\�J2`���/�҅������uSb�Op4��F�����$N��ֽ]2����v*�CP?��;��1����`p�v�YF���8i�Q_l^�e��(�"��!Z��k���>�Bs7v��y��.���MuA߻��R��['Q�i�w]Jt����p�?��]�cU�E�����7�n`V>י�J?l[����0��t �N1��^���p�bt���|���lG� �Z!��^�p6�_S���0jpRJ<6���ˌoV)�h	~��Nb���G�d��z�q����U��޹�w������
�e��}Q�#�5�#Fxwo��%��e����/���}�Y��ƒ�剁�Օ�2��{�N��Ͽ��߽�~t;�(�`��Q0
F�(�`��Q0
F�(�`��Q0
F�(�`��Q0
F�(�`��Q0
Fv  �	�$ �  