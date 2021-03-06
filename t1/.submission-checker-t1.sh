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
� O�[ �=kW�8��9�B��C���da���gh��N�����$
�vbgm�1��=�������ح�Öl���3g�9�$R�T�*U����0��^�j��o�������;[+�_�|�Y[[�\]�Z_�������wd�ۑ�<�0rB�sF���Õ��A�(�����h���_�X{���<i�_΀�o7z�>�俵����Fg�;��p$�?r���-_���^�^�,tj��󽝅�������5��>:9�yga����;�io�ם���i{�� K����I�<����t4�������B#�� ��%�FH8�tBX��u�6|z�n��^��P���C����� �_����ï���#�c�O����7���qC2��?��ϟ?�C3#�l���ɥD��&���sN�p�D������~p�e����.IX��|t#��1���KH��Ԥ����l�ipI��б���>=�77מ���<����|�wгO^���Zƿ��pƽ%�Ϡ�1\��O͵�n��%azD@�&�toD�]�?��>͐�����P�I���WA�:t.�6YX�T�>"�/������$�'~����5׼�A��t���^�5��Q��{�"Ұ� �����}��и���{W`l�?������Bg�CX�)�b�C�!��6|��� �m���ؘ�h4<6�{����qG���hHإ�e�N�$�������2�� ֓�g���S�	�Y󶄲7���b(�����j�)N�@��_��w:�ޛW�;+�3�/�X&�g��Xk���ҠV�Pk*���AR�w��,T5᳧��֭� W��Y����f��#���jh�ʁ_�ŨH	���|$�N� ��/n#@���	�|��ɻ����w�a=��->K�?���(Y�LE�2��|���0�) b��a�H>˵�1,4�_���v�|.�{����|��U'������-��I���3rN�����Ճ�N~s}=��wVV���c���?�3�����������ɩ}�;;��w�����m��څɛQ�w��h
�oa4p���W�J�XخX����v=7j�UԿr�&�U��֮}w���6�?5���(j��c��;[0+���������,�o�|H���C#J/�	P |ڏ��}�U��'�_٨��o���,A��ğ4R聑�)H�z����\�5��l��)������o�ou2��i��q�t��n��0�A������Y�l0r/2e�Lc��� ��^����n'�7����}�Pt]��}a���L.�]uY'�F$����G�f��å]�v�[�l��]�Cˑ��ȟPOwF��sƴ�Q9���p���	�}g46вC�������� =+�Z��j��O��"F,1�q��r=[cg5L�@�
�&X������ڰ�1d�?ز��k��1�M�VT�A���h���l~/f��� ��:�m"W[��.�����8�qV|�oyxLh)������"/u�ǜd�b�/w�(K��D��u�PڄX���%��H��aK@�N91[dE �����*��>ݚ·8j�={ux|t+����!@�>���6�{�*0����QW����,�c����X��ȅZ��CI��(����1�U����L��A�
	UҴ�q�·���yO�v�����+7X7֘�2�d���If�4O�B%Pb���~��K^��ף=(^��M�8��+6G�5�b�ȵ `"Ca������+��ZZ�|Z$��m��������[C�Σ�:�O�͐��;�nt��@նU+A���K����q��y�?��20��릮�J���\"�	v	�h�K����pܚ)�Yp�.�K�(�0������y`�l��g�պ�=z��s�X��y|�Y�R��T��=KJ��m�\H��e�G��/i�0�}�/O�O�O��[��%��Ga#�m\N�]םU��<�
>gt�#�xɠ P:]�7��ytm�H�.����˿	(���0vH"��\��;(o�T{kg;c��P��N���%��a�-�����XDS�%��T��}ݪ���L����=����z�>J��k��k��������Q��o��5��5ؿ��#�1��3��Y5U��� mA�B?���Eީ�<2rjӏkz�Ծ���6�}X��-aqE�~����Kl�����Ti@G�G:�L� )v�ѣ7��܇ӉG��$G�k㚹�v �E���%�.YZ�`
i-��t3�,�B>L�'����ߪ�}y��Vm�A���N(n�7�C!B?"�ce:t���@+�œ��
��Z�bڊ0XF����ʶ�(����[^���JVשR~P�A{���5/T_��yRd��|'���� �4F��M��BE*�FV,���\oJ��2�tX��Q�t2��yn)F�� =�v'w�dp�v^6Wۦ���yLRf�ש�����L��$�������$�[�Z����[O��c<���:�;�{�#�o��L5�;&z��OM��!U4���T�ʃOZ)��	�S�&~�?`v:� m�ψ7�&h�e�g�,4��Q�E��B#b������,������0�6R��hz/�vl��Y�~s�w���_��������o���>�������e�Gنe�#���V�2��M`�!t��}�i��(�����y��������jg5=�;O��Q��ϫ�_N{{��?j=n���4Rjlaq�VB�q����u��O=sU%�UC��8ի�Q�f�sSũW(ѺZ��ݯx6i[bt�L�`�m1����`��`�N����_ؑ�@�&������_��Ǩ���1�x^�� � � ��F^ߤ!��ފ0�W�h��x��)����iv�wzz����7t�M/$Uу�p�,HQg$ܔe��+� �2��T'�#��a�o<gGpJO� F���!&{������&f��5VDh���"���*ي�ٜ#E�2T�~�}�׵�y�B�7=E��a�?�������f��o=��GyLY��Ǫ�-4�F*/ �/9t2r\�����e���C�Nq��-0�*&�����cWЍ���h��5MJ�1vߟz/�KQ�5�w�����[5�z6+�q�>�y�$��r��2�"\@�Y�d��j�|-�;�)�h~�z�^c��9B,QDNP��$�������B"%`%"��^�������)�����7�����!���Nu�	�d��Gv��Hu�$�]fkuNX��ę��a���*��*�����p���,���E�Hsڛ�݉�h��C�L�+'��V2;��O�����`��YY	0������>K�N%5Xm�b?_v�)�G��x�)�q��j����H�����7��/NL���!���:6-�%��\EAB�(����K��7KM�:I,aq'��I�$}�^ئ��B�/X&C��̹B���a�D������a�GgʪZ���/KK���+�
Q����6F��Ko�W��wv~z����nL�Ļ8Ռ�Q�i_��Gs�u��z�`��4�,$�O�U �@&������M��k�c��~��}�"���D9�̲B_P��΅ϮƇ�:#���볽��z�D��i�3J����5L�q��
�*�o��z���{_��ǐ��u��p[���J�׬�Aw|�%i��|���.��딨gQ���>y����F�@<����}p�&��3�@,���ܜ1鐤7ӶO�>����+��K�%8�lf�m�k
I�vE��Bl�l$r{�[���A.@,��<D, Z��(�`���|&2�wr�,WW�`كv�"�&=N���DIF|��tϧ��קg��Y��V��6gࡠhQP#��������m;fI�_L�ȣa����|�T�̕b�p�:[���<��qKI��ۨ[xb(�ύU��>��ģ�5�0���:��x�8�� ���S�]A�iݶ,e���;�9Y�xtx�a�@����r�0��ĩ*�e��NS���M1ST&�h��U��D2��"�����ηAf�AX�� ����@C�'Fى�f����|I}���D� ��+�y�}����qDZ�"p�:B��e�r�L��!���O��	�0�.C�-�`��I�����ncu408���$��\�x��[�:�c��Ja�؝˩�%}8���zuʬB8�@�맼��j��]�֞��l�/αfel�qVF^�C�2����d2�A�g#v}��X�^a�ಾY��-?��/��W����K����"��+���<�ۥ|7�Y����Y�\�K�,^TU�g�q�(P�m��wK%,�`�B �#4]G�
�����7B�F�pzd�lw���[����C��;�>����n�3�%��Y��7�Q�'�
u���:Q[L]�3����3'��)���@�;�}��y�ȍs"�t+���h�/0�Њ�_,d�B������s�sc�7�$�@?���i�E�j*%�:_�q��!�JXc]-
�4����	y��N��G�Լ���L���|�ќ+i��]�S��7I��-��o�Z��_���;)ͺ(�I��d0��x1$���*�b2>��:���0]S�y��r���{0ղXr58L��$�� O����E����e��}6C�/�ł1'��#v���̜�e���*a��tw��ֲ�2c.c]�کG�v8�i0���U�Q;�GL@����0�o������.(�}[A�`6�I��t�ܺZ�Tj��ш�F*V��%�ƌ�<�W9�V�%�U���nM�|,ȣ*��K n��M,�V�m�&Q�2[�����{��Γ�Y�fo�>/?�R�l��U��܍��N
p��Vgh��T�q���z��ڔ(Ka�]�!�-�98VG�u�I}Ό�zFn嵸³�E�X,�nd���S;�<�E�+�rh[��&�n��2�\c$��J#�b�����Ek6~P͟{ibS�f�0aIF�R�8���hذTu�Q���xwv[QvP������Ƕ%1>;��6|ٺ?0g��p���{��n@]ε �l!�ʹz+E�8�O{��$H؆/��,*�&�L����Ra��`j��J��f�o+�3�����u`Ez|����y�C����1�X݋����R���2/�_���w�@x�'0Ui��?�0Š� ʢӻHR໿ 9"U��w�ǭ���CU�lҷ�*�6bl��1���J�4��ρ<�iB�KB���a�+��FK�r�/��h��׮Q=��q��s� �A"_���g���x��
%�ʨ/	ZMu�����}���'�66���v�$.1A�	#W�	�?���E@���6	����#�qt5h5�ڶr��~�����~�����'1g�p�'����S6z5{��n%�dB��O-����8�F��!�r��7�&FI�E�"BF,F�Ϡ�g��ƀ����������D��օ�����?�^9V�o����8��<�;B#2;��o!TW��ʑm�I���눧^ĩTG��g�?}͡��e���^�nx_U:�'��8��)���ezM��Y�<���c�+,��aN-��$��H/��#����Cz�/{'��c>.Y^�|0�� XQ�	�**@���2N�[����6C�7����{��!R��j5��.P��}���~�lʂ��eH��8���D�)e2�Yc���6$l:s2W�����.׋d7;��>>�K�!�����!�>���O"u��Bґ">��F��r�
R���K���/��\u���$����+��������Q��������77�������OG��{��� �A��K`yw�y����_�e����]sȽ3�h�$���R�2��� ^+����i� <ST�,#~|[�^��)e]� �ɇW��	?
�̬̈��!�53�����ݢwKŹv��@2!Ht�]����;�ў���WZq/aH�Շ�$b������	��~�����mm�*���Э̰1�2K���qV�2��K�~z�ҟ�)������k���n�?���x
_�d�5�Y^Ȥ�Z'Z��/�I��-��|Ft�3p/��8��@(\Ų:�%�|/�hɱ��=��0���D|H�"��)R�ڻJġ��T���*�*Z]ҷ�װLA���,;�Ir~�h?��2��?�hdr��4�ܢ�T�>��J�<]�%���h���k�yV��1ڷ���P���殕��>���~{N@X�sW��;�����0�@x�O���՛��1�w�G��Y��jp��w�L	����,��$1-yd-g/��XIKjv���+��V�qY�?��U�M:��4�:���(1܂����wt�m�g�W�e)#�(��H�E�u��Jr2��r����>�I��G��C&��ۗ��uw�_(�u�v�7�E�{�{{��۽�֚j7���Q���h$���{��PLAFE�W�R�K	u�,�(f�Ȟ,��<�������vV����-�~�ɚ��3ZUÒ|��m��P��?\�E��@o���67g��|�����G����=�������5<�S��Ѳ'mx�����m�DBS���S�=�Xs���	�2���?��鰋tb�VY�էg��]�=�V���?Ч���M\K&0�ҝ\7
b�Tvsnr����m��`��:�zw#�{6$��L�7��v۹H@P52,N�d(�p�KCx�z�E��k���!�7��/�SF)n�.P餴U��Q���\��"�/�@ع�+^�]�Wh�-��]�Ƥ;��O�*�4W�+18��`V�L��"��zZzKUL�e	�X�LoRLr�䙥�1=|���viL?���eJ�g������ZV�Dt�<fURe�ބR���F �6�,ՉI	;�P8�3S=	�,a=>=�9x$`��(�����@�oS<-*V�aV��u�A�2f'H#@[��C��k��!_�E�U�r����
 �F��E�C��9�`sϙ#U]˃'Ʃ/�Y"l��V�W��k:h�-�vI��D4�U[� V5Վa�.W�ˊ�ȭ`.mM<�'iXg
�?���i�����fv��*8��[���C;V�'����}�w��m�_t����݅��>J]������U��1�[h���N����!�`���X)����Q��/����q�i4���il�h�k	*��ym4~-��џ�@#@����̘�yM��u�ʎ�����@=WE�`.�s`*��|��9�C+�9�6֗�:���0_� e�^�n�����CO%��������"ޭʌ�V����Ӆ����n�����j�wk�,��{(�w��3��� d¾L�v���+��-�~d���,W��~�Q8���o�|�>�?��?��� �{q=fG�t&������ ���NK<x�A͚] ���}�u��T��3n�cS�]�v�N�ݑ�	�f�1��/���<� �C�ˍ��*�x�z�/4d��_bخ樵��O`�+Ki�/��4����.��L׍���r}��'F�����������^.L%�Ɔ�����_��������}E���Iמ.C[�6��6�7�?�@:��%�0��OۡD�F��x�`��p�ʇV�Ey�%W�ň���O����nuU���X������dt��n}k����/���^�j�k�C��G1�]]�f�2�m6����-6�s�b�O=��p{B���o�;IA[C��u��X��?l7`]�ZCnh��qGm��� s�8�&f�+��D�e"�;�8��^c*�C`~H�)�poI���r/��{��3@����_"fϺ_�0ph����3n@x��Ɲ "
�D�`Hy2�'���7�9Kc�2��L�A,���[C��&��	�M��m�ȑk6��F4��Ç6
�	q� ��� L�T$�޲��xC�{��-� y��qL���tn�}�'c�Z����:ҁ_]�0Ӕ��I��ǌEb�ka�y�$f^:\��z�j�S-*<XH1��Ng���Q:(_rQЗ��	���Bž�2�凞���=ȴ�&����0 t� �G�A5^2Dh��끊ĲM��{��������:����_��8������%m�l��svՃǞ^�_0g������ώO�'�S��
���_c_��t�˸JU�Lr�B7 ђ����/jw[R��#���@7�_c�.�@ē$�%ՠ�;�:I�x���C� E�PX���:vG��.�����&�̖��	��.�ΡH��p�
����Eƕ��0�y8}jɲElPQ 0��ގ��;�,����a�� ���Կ���N���$�����a�������7F�ѾQ�lF�0��m��G��I�6��x㶠�RsW�>�~^r�@��V����̷�YK��-~�����UG�'����N���'q�A�z!}\-1��%�8�����^Y��墷�Q��y�9o�� ��T{���J<�Kf�J���Z�YN]Xw!��n�A�#�J�7��`���v���𭯋��.\�G'5�ꟳT�L!TgĄ�V����
��q��p��ܥ�+�
cZ�Ǝ�ޖur|�;�� ��ѥb����F�Z��-�&W�+?���
�]�Q/�V~���0-���|���U�F��^��Bա!W�Uz�<U>`Qf��������������O=�`FA�Q��t�w04I�0i��d�f%����;#�j�D�P�x���d����0�+`�%�Tܟ9'#�BU)z�Ş�ȾQM�B.���Zw����2LS�9�#[쬩�|��|3yj$�.v�x6QD�*|��Y��V�[�u�t�.8)/��B����)ǝ���q�PҬQP��D!����| �Klp�g�G[��2�g�׭:���S��ɵ�ju"���𭉢7���d� e��a�!U"DU)I��%���IU9-��V�[U��D��~|���\��Z�F>'K~�_p�{G��k�����y|��7�,E*(���̘3�ܐ{Vy$33�-�ۚ��V�Da-�k>F&�VW�vM�a���ʋ�6�T ]���Ƣ�n4X�*�[,�ȺJf�O6?���ݸӳ��γn���F�RQ���p9� ����]G���Ҡ*���,�_蓐��*��E�e5}v��@��-OU�<�m�u�3X��j`%�۳�:[�L����*K��g�@�Ʌ49%:�n�'�/#c#gO�e�x��}Km���ҙ.y����CuK��uB�^��8�$T'�Mm��HT��T+��L����ܦL���Q�mE�g4�P��o&�[�g0<[���:�.Bgu�XK���wJ)Z3�D�lhs�t��]�9Uf�Y�ȗAT{����w�Ɲ�@Q��Dx��iPˡ-�Ic����o8Ui�6���ͤս���0�Ƈ�~,J!�,C̿A����olU�������Q.��O>�]]�g=����iZ��W��e�}����G���[�[��?�K98:�r�g�@�9f��:{`�b���{�q"��I�('t'ǟA��3�wt|ֻ����{��QND��p>�i�< �oS�ƌG�bf��!F�}���*���N�?��sf���߅��	�P���H�'p��"����!��R��
JW���@G�')�>98 �)	����ȕ?;�W��t�_䫰�*���i׸:8p/9�tI.������(8	����btr��Az,�;fl�@& �&"�7iw�s�'�pL����$7��7�b����u�K���N�0��<==���������u��.�1��I�1�M�]3�,��K��@���Ӌ����� xw[�l` � ��AZ8 ��ϼ]y����$&A2.���P"%�kk(�(�<�lg^�_RR��6�u/�I�� ^�u�r~��Ƥ7�;�z���g��FB���0N�
P-�X��_�
�:���OZ��Ɛ�!�*]�	c�r Z��s�lp�ӡ��1�c�$�]����>*�'��C,�}���bT����A\������W;�L�j�!QaCc⇋	9o}�N�?���#:�T�4�W�k��o@����*h���EK�{�ez�Ԭ@i�C�������B�9�ܳd��ޞ���"K�7]�g �mG���	؇�c.f$�G<� �č��J�7�5���Q��zF1��h-�ǔ��f9��#zzl8��7=�X8褒�ņ2eޖ?.A�.h@[��0@2A���:l��������w�
	��נtl-r�	=U�<@����8'<��L�	���qoy���_b_�_ҩ�̌g��vA����.��&%�60j��o�9*�>�g:�%	R��e��s}����q	��=ft�*l�/�Q҈��{c۾�a���~��)<�M���p�: ��x\��6Z�òZ"d<i0�e<�Y0�X�d^8�&�A�x��gA"��eFZ"�9���2�
g6�^9�s��0�ާ�D�t�=4�y ��R9Z�m�"|~��k�bs[�43
[��:i�rq���z�#����/0���V)Ϻ����M�0.L?��g|nĽX�XN\?�l�NhΉbeǸ��5��WJ���������	8,�R��
/��i`-���	�c��è�ա�Ճ�2��7.�!T#�lV#*[� rv�.��P�d@�^BK:r��M����k9I �������˝|2�N�����:�d+����YFq	h������� sٵ$�1�l� ��t��(�U��,X��e��vu�cA���F�C;΋�(��(��(��(��(��(��(��(��(��(���?�S� �  