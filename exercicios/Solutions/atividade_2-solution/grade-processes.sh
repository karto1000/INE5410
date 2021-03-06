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
� A[ �:y|E�a�U�A���fB�LKBBB29��C"L:3��a�{���E"�����*."*�*�x!`�EP��PDA��Q��c�'�������GRS��]��z�"-��4�0G�j��A����uP�E�_}"������Y�#,V[L��_����D�G(���Ռpu����?}�����~+�������&O��/�)7m�����hi�j�����YnW���?����aͥ�PA�e�'�D�}Daj��F���&�b�sDnNf�.�Ȱ�Ӈ��O���|��E�N�%Q]
���t���{<D�#1,��z�I8���	��!�D~�d���J`�xKy��H�9�&�2��
 `+hѮ
�y� 4l��=Hd�4�c-�h�b��R���^���.�d2��,,���*��Xn�i�$��.�U�e���V�H��HiU-Nd`�q��,*U.��fDd�21D�!MXu���?�4zi���o�������f�?p`�����<Z�'2�S���ܢBT+���qc��0 G��&�6��-G�!�#�_���d"؟���єѴ��rM�&7F�z�	T9��t�K'�+��<-�=�C>��q��p,��M	�T��Qq7��(�.iY9-]+Ҭ��4���3�s�#�t�r���^��LII����YH��]��ː�	𳂦�8�Z�#zlR��i�ϳ���s�%"�x0� �^���*��,��P���`$JZ=w-U1���r�
e��i�@��G(I9����7�btVja�����'Y�Ɉԥ�JH���a8�k���$�B�l͡b�̇ ǆ ��`V@w� =h�D�RǐR׾x�@(9����bT6BiE#X$̓�$cC
r%K��) �J�K�`UT��6M��+�!��d+s�1H�TOd/%uC�5YY��"�R[L���!�'����A��+����x��A�W�K ش@f�����a�X����%�
�h92�w<��_Iy7%�&���h!�����5��0�{��Mm�w��ɤI\ر��X�S��)�j4h?*`"� ��8/ݰ��>�ji�����\"�9����0�0��oX�&�iT�g����RP�����a�\4/rC�!���y�b8�U3�iƱڈ�R�GK�T�A��t�j�&��8<��P��	2�-��2cd�2\����./A���(i��&�1B����t��
�"^�����ri!�j$ʔb!*8?�Q<��9Q�X*��ɔ-�)[S�Ȕ�g0�TlS�7���P�d����B �t3���'M�����7���P���i���b��m�v���*hA���
�f|��]!ZI�I��Z���D4d�=7#H�)?�8����@���C�� dpHK�Ns8uB�20�5�1 ��ՖA] &,!���gd��$���ꤿ�+Y��8��@�!�Y�r��Z>� ����,f��Z�6��C�:�cXoVg�u����M����{��8�æ"`.ui����I]k���(�jjR�H���+Z֘�ֶX���pM�I�u꺫q�ջA����p���$j: �p��o:07�DrTi�\<�۰�C���C�y�HB9"�_��<�~VP�g����c���*�Z��'��Ih�����b�4�]�[���6��Yb���G[�G"�3&gt7�;9�I�
��Fc�\�T������ơ<>J�@D`dBQ��6����̷���K-�(�i�k.z���f��LP4C���5��h�K��5-&��Y���*r%mr)EF$ú<~f� �=L��"9t��N�[����� ���/w����Tʍ<iI�'I�c�%�ʼR���u�M���^���t�� �ʐH(��JJBV7~�Ί^mY�$Z����YJ�
���������W1RU1z�'F�ɠRP��$��[���"!��I�)b����l�+A��½�0;~��AI=�LK�2�.E��k�윌�v�����9����NwV V���#�L7���o*��|��U."a͎��LS����
�{iV�������/H[ir��G��8P��c�� �@8�Ψ�@�D^?#r�MY7�7�았�=�R��2��J������T9Z���T�*	KTl+i�� m�`r	���ûHy�ܢ¼��$���I=k�M>�J��MK=r�������-:yXjA�� �(?�.PO"��ޣ��*7L7�����J�Akbp%H)�(̲��kJ@	���:=B�jT _Aaj~!�K�
�=����`K@�"�
 6(��4X��K��6!�[��^n��Cr��7E���UW������&�P}ym]i�����`0��+>����B��Cn���g��>T���]�ܜ�)��Kg�� ����i�;�¿׫���=n��%র��������\�uS8B�+��}�<4��J�	^�X�@��?pl�hT��WR�&�Aғ�o��[tHR�X�*h�O@Uض��]�j9��:p��ㆤ#ߤ��P`X����4����*8�`\"����W�"�xj�@��1�%�(P}D)�{8��pܴ*_|%��rGړLR;�����\�2h
�zK)*�l��$�k�d0���X�M�����"PP@m�d��>ց�/��KF�k=�#竑�AJ�q^\>d�5oL��j.��l|�rW��2
�=6��_E�q<ϔ3�C�5��2.�3��Tr��2�\Y��]�M ����~/1�W'��P�irym�dLum}g��]X|���YQ�r��Cc��}�e��#�E�9(�k�a���h%��0���fs,X��Z-"l��e��)�	�Wu3���%��tR�!�{0.� �à-���]����G��"�4�7B�ᐇ�P
2���BT_en���*Bu���?��@d;���`��$҉�:53*Ѱ�8�$��R^Q.�=��P&��1���pg:$j���y���I��<��@B�����ʤD���J��fX�DsA=� TY��N_D�@�ŕ{N��F/��}�ܬ0��c����*8~x��}��(߱*q��j�Iy�8�e����"{����!*҈W���mpo$rzp��\qx��x/�.�6,��v�O�	�%���z�ɱ T.�M��M)h�S��yj�����7�o]�
����B{A�0{NZ�sdj�p{����*%y����R>�м��!����p�N�<���f��4<)O�GJD��o�=�7X/�R��1܉��?�SgI�6�z!��K�y$p|� v��l�Bo���#[r�U�L{�r�Ue�3bȧXD�d+��(�J��f��"$�%��$�	��,n�:{�BA��Yc�ȁKJ��
3�4M(��0qu����@�
@�R�w ڠ:�f����2d.����pA2X�!���RQ	H'�_=(���~���ɀC�Q�	v�#'�\�)Ă��3��uZ�ǔ>m�".�	p�� �<;I�1��M��V��÷D�O�26�������rfL�G����UVן�vؿ("m��)��c�&�9&�erİ�w2?��%,|:�~��������m���=��[Uo�|�D��?��I�]E~���
��&���j����Y��繉�6��u��9���f��D��K���g�������:a�G�:�]�ƹ���j�٘K���o��W=�{�&��q��������k��Oy���W�����<��g�?*'���#��w��/O]ܿ#{t���>��Z�^�앺O^��t麯[�������MnW�������޳5o�~����M�����޿�}��Q�>v�#z����N]��Sv/>�?�c}��]:��ɹ)�2�e��8�n��	�f�]ם=x�%ӌ�^� ֜��0��zn�cscۓ�=٭+>���\�7t�-\PN�g�0��`�>��ۖ���B�����}���m�;v���qJSU���;�>:���7��cϝ�����|�ܿ�$������Q^����/���Jls%)j����_�3y����m'�nufԠE�&��dm̿���2�b�KKw���m��������y�6�_�P�8_�^=�ڪ���Eֳ|eo��/��6����o��ꓧz����͈��έ��k>�9�â������u�Ў��ݿ��?�'+W�ٿ����㊋��UԹD�䂪y�?|�<�v�st�O���!k�V�/^i��:qn�����,�����G<�r���Α���Lٰ�<zm��*S:���ऌʂ�QY�m��sϴ�I�kO?�cM��/̝�I�rz~/˽?Q�<qw\�m��<L<@��-;vps⒃�Hx�2�lbƤ�Y3i��y|MV�-��v9y���2��e��w}�����1v��϶��{��M/X�%쌞�ǘ�o��}�0��a%I��=���U5[�^\���xr���V.�o���M�������ͻc�}���ƿ��:t�0~~�M#ʣ�Ԯ�^t9o�����~:DDo������vy�cռ[�<�iO4,;޽��mY��.������q���9`�{gǬq<��q��U�/�0o�ݿY��j��bzes�	�<y�r[�'�v}����|*}R����V��uN�s۞�Ͻ�ljdױ�LjM��&lx6�\=���N���Hj_���ߺG�O�N>���);-��T�:�t��USz�2����<~�蝥�>zi_��Зg�.�>[���3˫���fS}��|q���y5C���ļY�~�}z��+����xV~]պ�'�w��9�l��8}�RǞ�&����5�����\�?j;���x��Y_=��rim�����]y����~xg�&j��I�=��q4c�[�:]��i}e�]��n|���ქ=:̷��~�m~���gS�|�57qT���[zFv�'�+K�?�g�����l]5�W}v��a�^K��c^)N�7���������}���i�N��?*���ԇ�m���yf�K�]�ň�Kw.\6�˺7ڬ���������h��mn���6�׶����=[:���ꚿ��~�ry�S��&.���%�(�X<�Xf��c��8��]�'�ydj�;�쉑O<<xY���-��������::oU�V;�Y�����v��-
���� K��))�-ͮt))!�?R)Pr���n閔f���X�s�s�^x.��=�b�73w�|fF)n�I��"%澷J�೾'I�|(��f@�I��=�����O^9|���4�u�ׅQY���H�.6�VV�za�c߁f��G��k�K��?٣��sC �3��z�P;�6����%7���W�T
� �>w���2��g@?A奷�z@vB$A]Lk\����!������Tޔݔ�g��`��$(x��c6
�(�8Es�u�D��c�ӆ<�֦C��k^����v�f���%D�������	�����_������h�E�/�����_������h�E�/�����_�����/�V�(&�T�{pw���1�r\���y����VxR�5w�����`��e�+f���ܷ�,��/_&.��`ew���)�B_�;e��o��#�<�]}~|�6
�sk�������q����է��uA$l�g��������|	h� ,�T��q|���<� �O����,>�)��^�1�*ܧ�u$nUx��<V&� (8/h����Բ.���g��j�����$u�/9����Yo��
���~��ò�2)�P�T��ĺSa����G���a��3T���������~�O���ku���� .h��n��3�9qU(O^�����م�v���hh���V��/�{dٺ�����0�t��mj�( ��� S�Q6��խ�o� �X���XX8�A{�'���Jc\Q����A�@��7��s&�<e��S6;7��A
���E�t�\��\[9���<:�@��{m&`��\�f��/�e���v�6���V�H�w�3�,��F�Z'�p/c�LBs��{L�f�G�t:H����B��^��ƈ��ZrB���Л�>U����e�v�ԣ�b"����B�X�����Ѿ���T�<sձc@R���|wױ�����Z?��'G�Uԁ��QE�ي����kV]�5�����	!���D��1�	���nL) �?���vH<JFk�	�3���Y��ލ�ZiЌSiYf���QIm)�
�<q/����n��戱����̱���/�	�����۪wj������V�$8��4���;}*Ni-A&���5U Qģ�b�R_8� ��u���tN�|V�۩爛��t�CJw9+�A�"ٵ�㖰�h�{�����5�S&5#|�)�:�J��T��@a_f;�N)UE���TX��_��wO9�YO�2����i�->]�p�k��W�(���:9�$���J����i�(�U�T�$p�J�RS�D��^�<�ܕ����o���I��9���P������32�E�X��{�([7B�Z�:6��2zE|p-�K�R�m]S�H�6`�%�E*á �Mjɹ=�[�>�'�C��O�X�(j?����
Y�� �����Jp�>,��gE38Pk�ÙI�p�mpJ��u��7�_����W��WΛ��⒀��,�-07�-r�����
�_��@�l
{��
�"tO	��\�%e�o󾔛�h��U�Xs~�p@���[k�f�E��\��س��d��Y8�ue�?ƶAA��)�����rV�29�+.WI��^c��*ҢTMQW�bDK������Ԅ��u���{��E{�����>S�^�[�-UZM,�� Y����.��l���?.�7r݄8j��0�笶�M�Կ���#l�f��CGm�OP��O�N�uܓI��S@-�gU�}��Q��D��1���������:���?��~=�՗h�3�ݒKx`�EB�%�ɪL4�}~�<��|����N}g@�]��V���M�x\�� _H�/�.�[[�KE#�+���+�Z����cO��${+R�7��s��T��*%V<�R"�/�kJW�|exԝ���3�i>K��B����N"ޭ����l|�q�G��ɂ��P�Bݙ�Hry���1�/ ���%�u�P�魪,�k=��8��R%�	{0!����I�����|�R�g��Ҝ����^��1o��+�k_��&J�re�Ws{�d�Ա=�|kN��ѢH�S=��;�D��Ξ~���L�'��"@� x�~�J����2�
�$�MWߨ�z�~Mֶ�)�%%(~�����+y�jS�s�w�`8�bM"�Ϸ��ګLfJ� ��7�3L�h�:z����<�	Ė���^�E8r1��˱�u�(<6��e�\���Q� ���j��y��ɔ���b�S���,!����x�����ZX�⫭�?`�����ǧ�U2�����7�LrǓx$��9`3\+}�&I�~s-�����^��>��M�4R[0=|9~�Y�(]��cp������oN9�rX�@O��箻_�egVZ�4�x
hYA��O��.�v��@��w)�W]���y*���C�&�� e*�:}�����=7�x��yy~r�h�_%%�pi�޶�Q���^U}���D��
<��yU��x� �>8Z��FM+%/�v�N�+�\�ƨ�U]W3��@��ѷ�Ƃj���8�ߣ|�O	���gIɣ����}��6n9��z����D�YC��� ,A�Ս>p�v=-��k:!���	�&fr��_�C��xk ž�0=�}*y���:���of��^k�s�G5�#�yHɉ�w渁��K>�r�~^�c��YU�B�w�>�ҕ�ê��\4�(e��n	e9R�s��<�6,�x˪���3
���x���߿>��7���E�%��������������������h�G�?������������h�G�?�������������hE��6�jl�U�A��e����KqJ&rD��>qE\?��!cX�#a�^�����5����<
9���܋�'���|�6�\�X���pU#�h��X5��n���;?>�S*���s� @���^w��	�Demx���	;��!O�P��ή�ٶ���m��o��A!Hק����i��g�I�/��^k�
����>%��	����U�!�Q���r����N�2�3�q_ph:Nv��_�.Եw(MȆ��*���>m-Y��N8���G�$q�da#^�\rs�[��Z�t�5���'r�����NF���?}%st�C�'� �C�5����to���8���h��O�a[�FuZw�ݔ�/�p�k1:�p�0�Tj���U�����K�-^�E~-����0[�O��ڡI};t_�զ]$��xk/��)�>������-J�x���M��T�T�˲B���N��ڰ�d97"&c� �[9����9�aQ�4�}�������-t�QY���3S�H혮D�����L	|=���	��̭�#�4g�4�A�9���W�-Ի9Y�[���)hM��]�3�W9
��ҏ���/�T��~�m�=N��������DNc��`�A�H�/]�͌Z!��?XGh����j'׽5 �vz1����Dy��<Y3i6��QjA�9�R�00\f���@��C�}e�y-�%�IA��L��h̘����W?���������5��7�h�������K�uZ��Uk�Z�0"�}|c�����bV����_�P�&9�T��c7 �K�BfҜ���8�7���_��g�v��;X�vs�;׾���M=?�o��[�c� -�:���@��&.�Z1�G*܏����/Y67���T��%��{W�0��8zx�͆�y�l���v+3�3G�^�R����ڎ'�H�&P�B썏�U��H�����p����s�C�\���E�#iP
��3�1I��C�ʩ3�w�/{�������%�Z�^�ڲ�'�
̖C���G�۪�c�a����v�Պ�$�&��'>�֖UgKL^o��e�Gn���R4�ǎ�	����MG�s�ª8�䐰ep]��x8�D���[�㌹9];��L �U����f��É����ۮ�ز,��DL�G+ G��9gdmUjT�Ii��Q�!ɜ�Q{uA��n��S����ŁB����O���m4z2����P� �H�|��3��ͥR��gIs!ML�@�=E^c5[��I�'ۗ3u�5r}O�>	5}����׈��af�ԫ�a��BtG!���	*DL�@�����C��tR���n�f����Q��K�B,\��BVr�^�ҧ���T�{=˺��l2r�/H1[����|�g{Y�لk2�_��p�J۟�G�x�2.:�����b��:us�"]��1�e��5�%Zŵ���|<w��S"ˢ�3S�n���o������|���K�N_��Yh�\�;�ƪy��C/�:�_Y�Mcsꃅޏ��5���N��T|��>�a�j�G1?���i�U+^S��ת��?wL��q�>g{����s�D�$�M|�F����'L7�^1��OU)Y]˞����]��̘��x�ѹ�fJs����|yS��a�����KR������`��Q0
F�(�`��Q0
F�(�`��Q0
F�(�`��Q0
F�(�`��Q0
F�� �� �  