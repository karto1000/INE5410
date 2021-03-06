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
� �J�[ �:X��d�:i�R��0������� �"�@j�۰;���ά;���V�U�fZ�&Z��^o�~���~j�����)y�>2ojE)�wffwga�n������>e��9���h^(�YkIl��6�0z��㿆^�z�_�3�L����M=a�`�ӛ�P��GR`xy�� F9�2�oz]s���������b���M�q�����P6Z;�b���ќ�{�j���x�!�[������#�c�6���K��i�*�f��KIT�Ԝ��D�I�a������#��iRR'��	l>H�"R�%QE�/��ѥ����$�1�a�J��c�J���l��i7R�����#-<=(��-����Ʊ4�ؑ��� U(�Y D[K8D�x�ze)�D�9��h�M{(��!����Bn�k�t:	�B�*��#�����H6B��p�y�� U$�4�RJQ��0�S�G��"��12`��� D�z§���(�.��=-ac�������{���������bа�4�%'?���I�F{\Җ��ב����ax�aH�#v��
`{N�������4;Mۊ)�_���F����<��J/Qi�0`���y�S�`d���ܜG`8��~Sqaw���#�^�*nsЂ�ʱ�
H�A`� �lKV�J��@њK ؐ���*C	,��[���֖ �%4e��֠��+C#���V�xsv��B�'^�C�V���0h4>$�I(�P���0"&����f�� ���v�o�æ�<�<E�$�7� <.Lq ����%����dD��I9����:�+�7E��V�2)�Zl
Z�������rP���=��!5��\���xBII���##W4�M�<�K16� ���'q؜�<�Z1I1���E��	n�
vTHv��d1M$5�������,��\C���i8d�\��4 ����J�˃<L��R��شx �5�(>�P����:�4$J

�|d����_J9%�:���q4��M������?��3���jC:�"qa���cN]�/&�р���E�#P*碫�SاQ9��$wՃ#��aNz!>)0)��T���zid�2�ZB�(��Y9�P���\�@H��h���2�Š�mT�6)#~8�6)�5����i�����g�y� ;�p�C�,��2ad�2\���,mA��X+J��d���4�rk�2��2���R�̠����`�`g��sP�y���PJȐ%r�:�i����(2� E�_K�)�"SE���L�d��G�\:��`�6���y��$�U� ��B9y+G#�#��djv�Q��]�&^��O>j�׈Ҡ�G��5��҇������2��"����i,ʮ^�!
����υ[�:Q!"*4�r���T,+��$��IˆP���?(+���a֊T�(��)���@ⱈ@��p�$��Ն�G�<��_��J�S:�t���N�R*]z���#'�92*h�v��[p�nB�;��,��B,�k��Ӈ?�����`�28~��3��3�7<�1���P�H>����X8���XK�RHG0Eb���^Ɏr�)��_:8�$�S�,��)YCS���I�4��K�Ec/�l�q�&F���4������rsL�\�XR%��B���(�a�N/0ӏlN�XW�<�p���u�9zZ|:̪��������J��q��'������\�6�1��.��ӂZ��A��_i��0Ɓ�A����Y�}GV�yW!=��M_��+/�O~��y"!&�'5�/F�I����ߝa�o%�2@�P<M�If;x�A"c��@V|6BS���e_�7-���P`T�">\�ed��2�#���4�����i��r�*m^��Nq�|�%�%�����C@F���L���
��E���HE�F�z�^��@����D�64l� 
��;��!�茾�zry��n����`��Wbt����є�#a��[��w'r�,6pSY�$l�	�o[���Bx��/E�87�"�$r����%���Q<����3��|h�FVܠ��Xʅ��&H�M����K5�L$>�	ܣ ��q6�jR�yΉ��Ԅ���z�@䥛��k* 	�&ƪ�馰 �ܼ�ay�.�0h��������J@����6 ��P��2���lB[��_j�C�	*�G�u�u�Nm�(g�j�l�:M������XQV��hT��\���y>�-�(���\�n4���g��?�pփHхU�;-����&\c`Y��j�kq^�2Dgqqõ��i��l�^˰��u�u�hW�%�����)���N��@��~�����h�I�y��t|�
ݢ��j ƢTB;�<ǀm�=Ьؠ��	�&��cl�t����
y�,+�A���Q	��U�<�ag6��8�#���1�-�Cї@�»���>��F۠��W"(=g�9Q'��%4��`��	����䢂��rKd�f�@Z1 [��Ф���k���j�A�n�Yc��b�d]�9�r���<�A.?����FZ��#��)!���<Q�:k㫨T��a����P�f��B��eJ9���P�$^�.�&����R
�W�����t�1��1e�c8k>��@��8� �C.��9il��Y�X?|HV$��kc������|Jν,L(����
f�Q��m�����@�|��[a�5"+��܉�h�� \J;�N�V�l|g��ׯ�"�4-!�P��y(��k&ʚ�BKh8�`���c��-�����$�����ˌr4̃(NC-	)���W�U�xϱ4�In���_���� ,|D5q����N9���2yA�Qb�?��@�،� yRĂ Bp��A�P~3�T�Y���H�N8
�Zw�F�`�������i7d<�������n���{�R(nF�b-�!)�9�Q�^� �fCn��B�ht6N!'vq��	��.�}J#�PN;�qAE%��pd.s�<h[����s^��6�v��Ә7ϩ��~ڥFF��kv���~Z��e�V`�_���>�(R�%Vr��@��qv�KA ȟKP%,�X,y�ܼ���tPް��aK��������$7�x-�S\��v3�.�v;9���H���&��
J@�+T0_WH��\��5TSKJ�d�fI_y%��*�'A�5��q���~z�Ny���I��
�?���&y�a���y�@s,uo� 1N\.���b��e�8����t� �H�&�f�*Cd���1��T�/��N�M̾M��t&-���jHL��ٿZ�s�.%B�Π�P�����`������RY$��$_!�>�+D��;�M@�}'#��<Y`{�tAK�wb�בb���%:G���)�&6t�#"���f��a疂��/�����;��I����U�bz�#?��8���فhUE��<öoɬ�U�VdIr�|�;���~}�����u��]��9獤�&>b�Z����s��R����׿�����G�������c���צE|v��U�˷v�8^������UY{`\�N߬�U�|���oL��+z����[�����S���d\��/������n�c�����޾��n,���^�V�W�Y�׌y���BEف�Bf��\�����Qv��{g��n3���U�?���ӧ�yk����SΥ>�f�m�����V������l�s�~_�������72�R��7���>�ܹt�}�nDv(k]����mW_�v��`]Ŭ���|8���e���i�W���=�����v��;���*��ǓS��W|�Hi���ZO*��o_߾�`�O>��ᜒ��O91ÝQ��?�-�,�̨j�v�����F�t���sոҬ�=s���MyeD��u˥z=]�V���e������w����s��c�]��cԄ6�O�6�*���O3���Qsv�wz��0}x�Ћd���m�=>{�S��^y榦w޵��?���ecߡ>i�ż뎓��=������NO���p����{�ۮMW�W��1���6	�j�d�rYd�Ҕ3S��`�^�8��6az���}xV�C��)�C������s*++3[���A��Z��vlf��������f�.�z�K<w�����=�mn;ڣ*�:�����^�r���Io�N�Î�ݿ�>�l��'+vN9�,K�_//Y���C玟�ES9���������73z����g�L�[���Jn/��T�vPݶ5{�w9A��.����.�W����U��6��>���j��]u���ϼ}r�p�:|���q{��_����/���⸥/����G�U�{ض����m�D�!�9��n�������Q��(n�w�}�f�{���������j���Eţ_:����9��;�}_���w�s��=g:EW�k
�[�vv�������ˎ��x��e�>[���̷�D�ٺ�re���ւ����ܰ��M��w�|mݩ�����~��؋���}����^����w�scג&���h�.���zd������3�3{lr$�K{'�qg�Z3���ԡ���)ɗ2�g���[���a�#�?zJ��U��˅�k�x���/<���ҽ�^��56���#�[�XWu6�����m�z<Ï\��O�JuiV��M�i_�\����9��J~�"un�ym���k�9����ث�O;�K��擽w޳��5����^����V��K����IS�mW3m���gM���kZ�|Z�ԥ�Jcb[oz�js�b���?�<{��{j&�?c��;��Ȱ��[~v�ȳ����T����K]㗭<�:���^����ʥǎ
��]v��{y]��[x&)��Ʌ_�}����O�/�X{p�Q%�/�u����;�O�?��v����'{��=:ǱwdR�%�>.�u�8%�ֶ>�n9�.9��yO^�7�斢}G��n��k+n^�������?������!�O?V�Lߖ{��K�ko��w��ߩ���L3|����yG��T,���/]Y���
Ǽ��j�	;�����rO���{[=�T���ۻ�������9�m۶m���v&�1�=�=�m'Ol����W���]��i�v��}�����\�>��s�ŹVN������P3�2�{�A��*%~R<I#�w�e/H�W�FV'3����B-fa�|�h�X��#pNr�'zH�<�T9�T�nO�4md9��Zif���)�����[V�C�vi�A-)���$������4��!�p
�Z�X8�J������o�Y$ ��̓C�?��:
��
|��~�(b_��3�I���B��"�K�Pc(�o�p����oC��*��(��<(0=��n�� I':l�T�P'!ϸ�5)��4�P\�T��d�Z	��?��G�u
��5��r@坉���6�]g"_1X����&��V�/�Y�a�o�n`a�g@���?�R���K����/H��8����p��-4�ʛs�X��F7N�	���bXH���ݣ�2������W�V�j��L��H��I�B}�ypy�Bk���%�"B�.��_t���2��J7T
6������은��v�Df��`�}L粳��6�B�<�_6ǲN������#��L?V�w����0ݤ�|�qs��
�z�~ּ��W7XW2"i���Xu�x�q�I�&���H����ݙy6���iC����,~�E�D8��
Ӈ)�X�M�JW���Vsj��A���Tք��QPtn�.R�m����⪆r��B"�l!���#3P_<�d����V���/�u3TS�B5c`��1��A[5�_lN#��]]d���L�:p�U(�m��^=����77�s�&��y��}���Y\Ջv��O��녭3yr���2��lX�j/QsV˖���F*ٱhnfF�)�$�}>���;�VqQN�<fbecJy���G2�Tl��2�~_�QT����n�m)"-IW=�T��y��`?�e�|�\IK5������H#;~a�j�"���t����ֿT�Nba�/�#5hqj��������u�3�Ѱw�tA�OU��׈��������$^�U��Yf�b�Hp��kH��v���5����Ge�vA����=5T��׈��N�?��#�����Om���Fk�s��|3�0ui�WS�݌L��֕[��9~n�N	`[%�V� K�����v��z���4��a��W�j����| 7*�:��|����(s��M���J�E�-���\�7bh������MC��_��\�"S��J:�35K��]aRc��sx��x�="/zF�%�wo�$�>6m{��h 6h�".�Zٽb�8�rp��l�;�;,]x��W����ϛy��-�[��� 9v{@9n��y��9��gO{`�pf%pmx�.��۟�cv�|���BZ�O��ol{�����f� �M�u~ߤ��h�k#���Ld6�2��A>v��	��PU�}�!Y=��[cadZ E�MI����D�C�1��A�ļ�M^}��������Hrw<�m�N�E��%���4⌜X��۰p��H.e���`fV�G6��q��8[�AF��@4�I<jjs1XQ������xJ��qJ{�Rd������$���9&�	� ��>	'���`,~��(���"�4�~f�6�g�dF�jf��O�?��ɂ��;��?4*�����\���&�\o�1Zh�q��WTG?�S�����x���p9��0d�gO\�R�X���l˶=�YF9��_3S8jl\�Xm��X��C^C�$5����"T��ό>LԔ]��3�}F�s���/�� ��^�B��FE;]3��q���;�O��;�.����;,~���2��&�f]���]��spJ�����NSC,�c���ld����rm'����[Y�?@�����9��`x;m��P�n��!*Ñ�_�����OΉF�Z3x��	��ؒ�]�U���1��|���'��*�Fz<�t�>O"j�[:�:��X.E�H\W�R�'��1�7����~�_�Ӑr���TfD���Tk���։��s-I�Lpf�Y�I�['��≫q,=�.�`3��y�gT�'taZ�J��dD|�ջM�GhC��Nz���3�R��萹v�h�]�s���7
�p��4�@�>ZT�s��@GgI�ۉ;*	M,[\�G�����$����t_����;�y��[�]$Jj��_�8�T�M�&�dԴ��r���-p���������=���^��Ի�V�+�k"����^ǌ�\�EF�%���,��J�f��IJN��PQ��5������g��P�2��ʋ������2�K��Ad�P���I���Y6��?P0����<��%V���$�it��R����f���JЅ�9(2&�:"�<h�}����~�3T���e�8.�����T�Ɵ�ɨb���au�6���<����l���h���RÃk�{ui�C�gq���`V�s�+��y�wpA%nS��[����و��������7j�.�Q։����PϠe���v���"�,��|� e�k���ͥ2!\J,J�P9A�Ʒ��9ϛ���j�xcu�)ֹS����,g�~��Y����#�%]�eG�ⵝ3�|1[/5z�>����ڙ�b������_�z^�\��`�U�S�4x������
�D^Ak�K���+��#�Ͼ��߯m,Z2���ƍ-a�,��?7V�Ն�u��L�.���0y��`V�6\��g�2M��ɤ<��z���i�ʣ�D�����	��,�i�	����0dɾ�J+�M��d�o�1ZZ��߯�ZQ����j�L�L�(�ܪ�U>ǧ�ӼY��,��p$9N�-�B��;o����%뵇���@�tN�X� ����[5�I�Yy�̑��G�"�S~ >��F�ˢ����M�p3��Oo؈d�1��m��}4s�	~Xg��֦��Z�t&#1�r�����)�o�9�K�,j���r5��
\8�Ԛ��5Q
=�,e�u1a�a)JR���sűԐ��Pt��O��T^�|CZ�ڢ'�tW��>�X�k滹�� �|�ɲ���+���ɣ� 7�c�U���b���ً��g#N�^`����;R��j ��s�Cҝ�3�����'�Sቍ<sO����=�K���(d�|����ʙh�˙�W#�L��|���R��_A,?`�!q
��l0Ċ�}�{(�$�f�#.GX�Gn�˻�2�=�ۤi)H�/k7��8��+��������@�X,�� {�IU����	�������2�'���q惵6V2V|-ˋ*�Z~�$7�������z��X�E�]"������ך{�hI�`w����a[�9��o�Ъ�)�貛��K�1���s�T��Ə����0Z�8H�������<`.��Q����*�}-��A���&%u���hm��c�S/� +�*#�:��������޿����!UE$~��	Z'��,c��E�����샧��8���Z��΍E�	��9��>+�� Ɔ��:'�5�zF�D�A�6��a'.��Ы�)�:)���i�Ώ�B�GJ�[I�.��n���N���&�k������FXB_���K����&���O�F>S_t��� �]�тX�Ƈڬ�\XtC�Bi؂Af�mKx�w���l��D}G ���i/ <<�^�+H6+�N7�ߏKgBڝe�P�A�l�M�u�sN��
��e*��g��VkXL/|/4����w��L'l�[Ѱ	و�K]F�%��IC���Y8����'U���9�&JoLM��KҼK�r�C/�}#c����#��R	�5�R��0V��;N��BkDX�><.�s�����W��E�4o�Y�)�g�1�?v|������P�&�D�5��_��L���p��� ���7��!�4O*�~�jii͖%�/��Y��ܰ�~L���>�~�v��B+q�]�����`lc<��_�ј
4Ʈ;��k	9�ƬPT��G�3�54�a ���=���o�vմHJ$o?��l�J/d�ƐA�7E�a / F���J津�M�.��v$
�6���"E�Dń�f=k�s�磕9`Rz������a���@FQ� ��J������� �ڋ����'�I��Nر]��I���Cm��??�K38259]�pGi[����s'�},���ב���,��j���>���˭��.r�����p2�@	�VG�V�\׏%�L���jN͵��p����Nӝ�������v���)��	���@;Q'����3�&�{�*x:�������Z�h��L��lk$��������n���2�6�gD�M�S�r��j���܈���s�����r�ܳ�O������H׍�y~J�o:L���*�=zv2�S�Ia>�;'O�4�r�n�8���F�ᙾ8��L{��uf�~�D6�����4C��|�ߖWج���6�Oӫl6C~�h���?�c���-���rr�#�W��\�'�� �<�N�ʱ-J�GZ���۰'���*0�.]�ob#b��c��P����}W�
Nr�dP/���6�u�_cX��m��rK�7����ZXP��;
عG�)s�y��ޏ~��}���'���T��M������nlØQ3k����MGgwO���qt�;q8磾>E�t�ˁh)>ws$<�+�|�����Vs��'�ܠgd����<�X%��5���H-��[���ġ�:5� abdhp����e��\�&���m���J����{����9����������������o�������������������o�������������������o�������7�=������\!'��Ɛ)k�ʑ$S#N���B�#9�	�1�!A��I�I㽞�E���A���.��m�����%�j�|�[)?y��OA����}�C{k�����.�WB��f.��M=���ѹ�Wv-��$�B�%����0��M'�lHm�@�)���*�2݋ۧ�G[�0F��S�o��o^h�;w5�m�:@L7?!�u���K���I�ܻbqa|�ıŀ��(�ɷ*w��f�xIo�Ph�`o��ѽ�hGȯ'�F̱EO���=���
�빑����b}��OS�E�*Y� �*x+�tl��ľ�%�*;K�P����
l��0����=�f��(V(��p�3�J%UA�ݯ��
	��2�h�3��=T=60��!W�m{v\lMi�!J���Rq��1�C��ђ���J�_K:K�7�I����o�23s��$���K�puK���_Hj+�gJ��<vvQ@ON���AM�P�q(Ǥ��~v3=(lg�ѡ&��+w�f���s�wق^�F����f��p�)�m�p?K����i�B����|�j/�9f�V��-?D�+��{�|��`�Ql�ݸ�mX��k���؉���=?!{���KQ:7���/�وa��o%�-I�һ4��u/���¢�[���Y�(���4+h�� �o}���}�h���x�򵛨�bS�W�:��L�ꕬ���kt���
�&�-�Ʀ�f����Ѵ��]�^�1w�U"���V�ξ��
�4��2��Rx��hHg;Q��.!muQM�
de�s�HJ:����
�b�+ $�0��j�$N��*y/�kM��_)�%�^��6I���$��J�#^A�3%����7:α+�����złT-8��!���+P�x�HZ}��ٕu���Z{?�9)D$��ґ�����%w����=DGf���=M���א����;�yg?���%kz�-�u}<Z����c�}���$/gЛ��Q�o��H�h?m ��K�?h[|��
����$@��t��8��kH}6����j������DP�d�;H 7�A����)�������fd��.3��~S��"g�p8����ot����\Ć�B�i��OІ�����T��Xv��v$&�\����R!�A+�/���j"�0Bk=����%���z�`�����%8<#�ix�ǌ!ǃo���ѣ�D^�N:x�����m���(�G����S���py��k�g�~"SGȒ��>V���!RM'�~jt�D�P�R��q��9�{6�5�X�-���H�M�z����o>||�@��;'��u��Z*�RI!�N}�:�n��ݨ����e1����_�S	�:&T����f�l��K��Z����	J��޻��4�zu�:�;�j�r�m��G�.�du��H�Joܬ��� v宬>��3K7ݚ��0���9�)������I7%�bW鬷�����N�X;FD9S-�2NiOf���P�Q��l�4�*h��r���&'B�j�������E�"�u�\tJ�����c��#�K�bן���c�K��5�JP?����l
���[���D���,4uk9�H��T �=i˻���q:_/;%a7�#�P��gxߍ��x�]�`�aJ�$3jA�@�i�|�4$)��?J7��wTT����;���LvT��`�M���4�8�n�i<W��&�I3�l6���$(�Ŝ�m\	]�+6��Qd�$j��RZqCi�ʗ�O�,L���P��һ���G{@�w!��.0�ji�m*�vHN8z��J����R��M/�>���#��917��h���}cuc�流7C_�}B	 ��u]7	�&٢��k0`D��z�z	M�QS%=�ݚO�䞴�8�����D����Pe��"���>c�o���a}�?�?�F�/�����OI�$��q��3"o��P��"�5(�y���lM} cB��z���~E�L �;�&��K�O�DHH-�yS���@�1?EJ���Xo\�l6���^�"ܮ�k��kdJjlkH{?
���/o�+������/�#:5!�n�{
wI��bI�h-�Z����Zt0$�ڟq�}'��P\d��1>M�4��q��}?y��f'�/�G섿<G�i��̤�ɱ`ce�%��>eC�&2Z�'��e��C�:��E!#ʮjiq<����w�� �-%��}�^$�]���� ��c�<�H7!�j���TW֏p�Uo��L;�<=2#���wLӄ3����ՊCҕ�K���Nmr-�q��Y�A@��1�>�3��E�G���]"�I��6.u����162fE�ٛqv�6@�]x�T
���	�#��� �4�IIė|y�V�X�fdbT�h��)��Aj��W��8�YIȭi��C$�~��1xO�3������qgJjL��;^tSpQ0?�#.~��3���q��SJB�Kt���	{x�ϼ���ڹ��R�^�g�d�;˃�S}���,ȐpplE������]���k��'���>;��p��k���A#&sGV<�^�MM���J,�����;�H���t3tU�p]e�:T����ՠo��Ri,�:���Ѯ��o=�`��'jT�j�� ��Q���K����n�����FWC��a�Ar�=�<�Q��s���^�u�r�ך�R�LBL�q�!NS�l�tc=���ۏ�� ���VQ��Fh�#cAU�m��~�-pm*�fs,��sr�pٸmp4n�pTk�=��r�U�1�j�,�is��k�Y�����
^Y#Y�W���G�����<{hyp�2z�:�h���?�=cП��Z���|�+[�RǱ�Ƈ{6`�$���A�<��RQ�i_U��Q�duܦom��J%�{|\�#�����8��D �[v\�^
V@�q��ϋ�b+Ϸ��F,0֟�ov���'��_�0��t�)fJ�y�c�����ML\�#b�ٕ �D�E��&���"�?P��5��Byf���	U����Q�eNy�|m�������U����j�0���A�=�T�5QF�)�� ���yb�n��~Y0�lf�uI�_Q�!�c�KNC��'���:���]x������]}'�2oDM\"�����Z�Q|��2�ysa�}Wj2t\Y��S�>|��: ���6~������� ���E�;xF��:H���׍�;�]M�B����o>_��d=aRH|��Fo�~znv��8�rH)�z>�ϡ�]�+r	��[)LW�,������y��Y�ċ���U��3��d ����>�y�ݵ2E���KUC9"%QO�#�h�EVk8��U��#-�j����U�5EA��({�b*�D��<�䌌����g�Y���F�c��l��xp�7��OFpɤ!�̗;̧�!�W9�#J���;J�l-ח���H�ƣ����[��(?�a�I,�A�5L����������/�a^9�V��UBe��FY)lu���L������d�<|`�'R�J=�_���}��v�,�:�Bh�r��ězfR�q�ߙ3&����O���UP\F��~A�[�2w����BY�b�!;�B�?���f�%��D�Q���H�m���s���u-����q�+����3{֥ 4h�	���S{�~@�OGķ����
hH2�������* �U�Y��|	]��{8g�rP􌩺�1$>bI7s��(#�D2+a�^�1>��@T�|WO��a(]M�Uo9�ǚ�1v5�x>�_D�>!l<4�����I5�: �*��
��ߧc���i"�@�\\�V�Ka��@��A7�~5jqV�m�HY�[����er���;E�_˽}k.�u`�XG*��}%��'��6�CgH�<؉�u�h,t�r���2�C���[zb�.ʀ�)�pΙnXO���/�k�K�+%N�g���r�x�	v�h��{�̖',hw������ıgf�A��h��H�j��$`,=�Bق��#Q~U�7�3E�#�-V���QZn��n��1�Ug���LB�O��|0�k}��A� 1����3:II!�q�$�4�*h/++�I�����5P�����2;�x��Y]i�kM~J�8��/���Ʉ�̇�H��Ie.��t��d��=ڟFb�izdjM��u|�㿓�#W����;J����r�2�gu�d䬅T�ځ�t8�-xI-#�6�H���U:|��w��nN?�~�z�%H/�b�4�2�m�i�
�e{���NH�j[�Iۊ҆>h{R�DFᭅ�����^�עAp4����t�A\�F�y-��G�+/���4�l]���'�*ͪ��X&��ydv/饯!��� Cu*���
B��{�\ȠI�b�x�B�<�mi~������rE����|?��bD��*1��!�˪�S�ʛ�UB���C爡[��{���^Q3���f_s:N�ٯߗC=���ީ����="����-0<y�I�e��up��Vs�����k ���E����P�;I��}�8c���B�����;�;C�7�jVT{��={?=#	࿽B��{�uh�_Z;Sj��^hS�ɋZG��!Gf�����:0B�˂�t���-��y�7�t�^�|��%�5��c��\/�9�~]s�z��)��%w7��Q$*�:�CN#8p���h�ɴ� Rv�fs�(d�n/{~<[i�
��s?�G#�L���s���M�gz�A!D"=��h'��m�]��>2����^��-�6Y��C�
Ed���"�>$2I	$�v�`�����t�T"14�[��z΄�-��k�})
�+.�k1�)��wz��p~�	^��Osr�x��N*������g]�ȉ }�ʛ�>�h�P�ћLd�㫽��3Qg��ׇc����s��!����]�Vy@���JǙ��������A4;n�<��j��V�\�P��%oJ�J	�廎�ҹݯ�%�$�&1�K�A����iO�7$\LVTbb�/'<n���XR!_:H5=Dx(d~�u�6l�m	��Q7�Y@9sÐ.7�@ܱ�]( �w�u���@��X��n�P������ �ID4%i�Ł�:��ݨ���jִZ����~)�B#9.1l�Oo�>i��z��k ��_;aK�cűm�˯kl�M88�DPďI��L֎��B�z ��9���b#07��mюT A��0I,4Y\�i��Y�*V+��(��Jv}@z�q7�q�A�� 6�|C��	%ƌ5���iaam�p�.f�`�+�����xqT�,x����p0���8�D>�r�X	
jㆭH0�-Ǧz��@�*t�AeL����+�k��?.��~\1!�E��߹���Li�>�;����Q����F	t!ڃ�@�V�X/]lq,�@�Q�A�7�:aީ
̋�b8<����l@[Hzl��@�LB�wq���d��l���؂�OP�L$DiKGƫ�vw<�p�19��������v���c.^SG��B���j������|�t�8�O���N\zM����D�Z����/��ҥ��v���v���O5��T�Y	_��^���!��9�n��0?:�]傜���)"҆�(����e��=t�թ�0�HU[P�)	���h4y���`�W6>�IE������jA�Q��F�����y���d�W���9?�N	ʜ�)"DN\���I�8������7�.�i]L�=ԕ�ߓ-�+�\��3�!s|gg�^%A�g\�շϋ����\�?O6���[I��8I �اfç�iӽ��C����7��,pH�y���wұ<h�@,Ƀ7�_z�Hb��}���{-�;�n'l:QD�Ze��_����;��X�\��c�ljs`���|���'n���ǦSX�����y�:�ՕLN�T/UWe~��.hK����l���9�ht���#��QD���ʹ���*at+Or���v��ޔR'qD@��;T�lx\�e��b�-[���ܨ!u�=��"�V@��)٫jHq��E�+ԑ�����Of�ZѪ�!�yF�t���n���:��@��D4>
x-O�$�nA� �D!�j9�*t�'����B�-�"($#�o����Mw�I8w�^���b�Ic��Q١35����6r8rX��ͷB�pT���m�;�J*3]{��:�k�P��eQ��R��x�V��0�eb�Mq�b��@�R��侷��A���wq	c�]��'�M�=�q�
��#ʓ8J8�L�̈́��RפF�-T��ܼP^�H��������?8��3���?����3s}��H�������o�������������������o�������������������o��?��[�M��W܏h	r�
�F
�V��xF�Җn����>�(�]��7����ԚN$-�g(ŀ�N_H&Tr����\������E6󱐛`����e"��ݍS�ۿO[�_�*�;ַ����]	�v5-o|D����`E��.�����Y�*��EZkBnt/bv�7�����Z�C�R�?˳�.�-���:�]�OZ����=_ӗ���&��p��RJ>G�w%��'�|{���Zщ�R����7�����^�4�~f�ի�804�~�RO����&YИ�ZQ�hւXiR�,p�`��Ƹ&�F��� ��P^L�a �|�\?kX]j3�4u@��i<AP���r;E�>wҷL�]�`�c��ݭY���0ק\���q)N4��Ɖ��G�d�p�Zq�PX���o�h�x�*�48 =��>F�]]���hYϖc�)�
#�6?h>cF�������[M?3f���5L�&���:~_盒��?��ؑ�������u�o(��At��O[𠋙�wd���$/y�r��8�:1�<D'#��[��{�`v,��vU]Q�ő�H����V]?��
�;_�y�<�U�v�p��E�)��Va:�eS?A��g�!7���3_�%��ЃN狥lmm��`�Ov�qܧ6�	.~��Ŷ^��J��I&���ￇP��.)��&Re��k5�H���|9?�i�� ��-�j�q�V��
+#�� FqTh�r�C4юd�l�ޞ��l�>��tO��i�h����?
�V3/u����+g��s���1fFj���0���S]�אC������_���i/�Ȉ��Q\B|#�(&+���MG�.�)k���+R���f�~��o�*}���(S�?�T�(nV��[ܫ��BG�Ė���w���`�!&w�e^�(�>�@�d�Ew�r� V{��.x-����Nq��h͇C�n�e���?����'�d`�����W���2����"����e���L5�훕Y��	�`����l�;�ڽѻ�SP[�m�	�d	m����A%��g/{���l�`��4�ʶ�����	�8󏣨��Vc4p�Eԯ��L�5��Ӏ0.85&@=�)��h� ��(t����
y�� ����I+���-�=Ê���G���Y����/���>�\�r.�4��\�-$N��ԁ���� =���>	�ls� ^�b�zß��b؞@��=�N0�!W�L�r*�(}�b@�����VH�U�$�m�Y��v�)YE��:̓V���{2���>�����<~E/�,ׅ��b�E�;-��]o���e�7��N��xoޝDN@O����1��o���8Ds^�8V<�R�,υ��0�Q1|dc�Y-a��+�z@�ջםv��c��������es�0�`Ba�,;��D�&�1��_�=�䟱6�O�9���?�Ì9���=���������S�r�������x��S�����s|SE���:F�s�?���;�4A~_��8)��9������ Ȧ�Y:�&412Ju�ؓ�>��vP:s���A9O��~��ϸ�x�E���4A1����%�|�������b~�xy���&�f���?�̱�^8���0.R@"��IY_b��h��	��bX���RC�d/-砡纤�ze'�`{��E`�N�M2H�{�QVCL4[� ����Ox�(��3�P�8����а��F RH��e��X�����+��5#)�� 6i���.�I�֋�*D�3�������_Iy�ZN�z�W-	�x|ʞ���w���sg64S!ǁ H���wU7SO���?���F�5�&�������S��S�w�n��bu��9e+0O�2�Zⶵ�v��˴{B��{�� ���1�6&��T��@E҉�qp�hv�ǬV-#w�A5t3ԑ/�#a�T�M��E�s�QZ@½�1a����"�����co.��s�r��;���A���Wq���;q,���ή�����W����/��Q����?�;��4&�f��1����gۓ�pY ��Q�wC=�ZeU�D��<�CY_/#,9E�텣��<\ �f�ύ�`Y8�J�~;��*�L�6�_4V���0f����]*�h>���#� bnP���b�PT6dd"['���̛�.�L�	W�π�|�M2���=A�&�@�F&'+s�Ic�68:��G/l�Ժ�Dr�Y;k�v�=>a�Nd~�@˸��G��b��T�k�2F��z�V�ߨԞ����93h=�s�d@Ѻ�˟�'>�>�w�"&����1�ݫ��Q( ���b��'Y"0���ZX���R�ѿ}�m,%���#���9B9�?�ت�,�т-��y��kd|���x�%s����G�l0=Dv����i�m��V4V��:���+��c�4��nigF�J�/@���NK.���X�4!'��>$h3��1�=�8�]���p���<T�k�_	~���U;i�ƕ�.�.<8��{�k}�T�7������+�L'�QS1��Puڎr���a���|��]�_hr��]˕a������Dәjw׫��L0<B��4�s<��CWH#�?��� �	j�
�x���9��Ϗ���%N5�ESF����pS;Ah>�IY0c�y��<�ë�ϽRue �F��_�Ő�9���DSj����y���|}����5�_ �*�K�jdLG(�s׬/���K߸i�s7���<�K�M�f�݊�v�|�ܕn�M������M��� (���(���3�>˃/K8��N�?�[��x�;vv;�e�i�-0�]���3�y��5DΏ��4\���6j=(�@�l���C�\ҙcl�����"��ъ����y�� ]�-U�A|���^D�3�����i�X�����*�#�R�츦��H4qq��4���D�R@U�5!��Q�X�N����Y-��(e��[F�z� ���*=�t�
�cSP�m�r��
��Rژ��zbsl-�1�A��v?�_n����ｌ'�*XM�q�:��o"]�,M��
W�cq���f����2�zZ�Z��+
\�o3}�1m�e+����e$����� ��h4��PT��Z�1v5�΋�e��.��b�)3�؄�њ�	6}�`�r��Ʌ��(0vuK�&���T��v��[� X҅1&��%�/��j���`�.�W�Z�\m�I��˜7ٺ��Z� �e�����^�~g<ʂ_��2B�A��DP�7<�W��*� ��������gp���Q����Ъ�P�k-���Z���y�is���O��[; y��P�Y���/^oJ0�<$"=-��F��*��y��kw4���-��\0V�h#��<�S�۩3�(f�Z>;&Lj�v��L�I�L�9�JGa2�\rȃ�T������2�s8i�������"B��
!{�ʚ���MK�!��Z m*� �St��+������p�q�������қ|����.cCX	8x��Bw~<H��&��������g�#m�p�J���ǻ��9L�[x�}��qk
GJ�����cZ8B�wa/�/Q�B{�
�T�K������Վ�py刴E�f$&�`��Ǭ��WW�K��7"�X7���!����8n拗w3ح�fw�+�������u��pI�*_de���QO���2�xy��|j��2�-Y�'Yj��m��(����oN 7�H1���5�D�� *�9�1���F*=j�9�D�斜{Ga��.���Zϫ�c��,S-S�����t;b��8�n%A�[��"�G��V�ۙ��XQǷm/mgM�ŏ.X%'\xU΀t��1?�,%*6�3��!�;f�o�-��6O��.�P�KEwb)�]�S��<�wR}�pEyod^�f�z#?�-���1�Q�M���9bS�)t�bMxq��<�&~�孜�;����O�Vx���6��.�8�ݫA�G��f��¦�O��S�O��၈:Szꋹ�7yn��j�<�Z8�-(i��eFKy���F�㠡�BU֊��O�%�4.�[�"9�H("��0��\��E,��Ϧ�,���]/��}���ꛐa˿�p0	z��{�������4�b���H��A��#���foq�I�,#W��w�Z+�����μ��y�wr�-c���:&�s�_��V֗�of4k��A"��M���G����7�G�����f��t#�	5E�sОL0{C[�|��������kZ_{�:��D(�`���ā�w�%,l*���=nb%���l��H����V~eh�4��R�c�;)�/(&�o�Q�
��>3a~��Tg3ۥ��`�ǟ�68�l�d�+Uy$\Y�BǓ�v�� p=k�D���~��e[K�(A貘)e��kk28� $�Y�8�xMn#K��"d��'��/cS]@:/�+��8�����Z�*R_q�FL�F��4+D:Iy��!'7�����c!���f��h�,*1�e/�7�Y�O�`@6wqtoc��_����c����`��`
��d�h-��%
]�m�l�'�ft0�����bg���|�{�dυ�[.�����������K��uj�G�fg|*����ʺ��m�rr��r��LO���6
=<��Mz�ؖ�W>ͼ�n��ƥ6��B+�Z���9��}�~�+�ߋ��Yk���31d�(�)%@~6j
�V<�P>�Z#)ӷʒ�j|�^\C���丌B⸝�@��?�1�7�G�zn:`U��0��Xz�/�,�#���%GIs�@q���ٹ��o�m��,	{�`�T� N2Αq��A���H��Mt�� ����ܠ<���J0��ItM�:,L�0d*�a_L�w⎌�-3���_R}ӎTA�� a/<����F���8_z��Wr�rR��+��4�^}��O^��3�=��/ ��T�@�)ԩ�'3a�侉���?��+f[,b������}�H���D��G&�	@�5�6��8��B�?9W���l��hF����/᥸������)iY��]4g����ڈ���n� ~٫�`:ʸEK�8���j�l Nr�"i0������C*��B��`�%������T�o�o���#8d��4�W�H�g�{B�N��^I��	�1oT����.�楦�@& `���������X�u��U�>�j<���\r� �{�<Ѣg�vWU�� %�@4c(����k��^Y̐������ڨU��{�Ġ�/e�����:�u#$�ĝ�(�� G�Es&NkrL�T�"�Iq�i�M�������h�?�ӹA8�QnС� �q�(�Ӕ���^Ea�@��E���؅���y�@�+�#=X�_?�$������'-��%7�u0�Z�������9�����T�����è��T%�3�U�h��l��تys`�Vk������������3Dt9��p=+�`. ��6��'qV��K��/x���";������:��*�!��1UC�f��I �1޵�W�eFH��Q7��<��`���F����y�vbo���5���1�.�-eyy�+MVȳ����+w|A�h��ӓ��k֣s�}*D�IH1��@�+�2�Ei�9�ꎮHq:9�&6�c{q-�����XnKAɩ	d�k����m⵳!���y�{���ɣY�ɢ�����twJ�g������l�����0����JE]��J
ߘ� �$���n�!F�����{E���~�R��7���I�*�vg��\�I�x\����(y�-F�/�{!(�J���5��W��P�s�2n��~�w�+Ӌ�0q��=�`��=�V� �Z�y=�!�$�R4�����Y\��&��N%��mC�"�����@wu�m�)��u|Y�さ�uUOU��]i)y.>��4}�����e�Ǩ��������!�g<�K~�~R�!�Im��Z�J�,
����9�B��m������������������������������J��oc �  