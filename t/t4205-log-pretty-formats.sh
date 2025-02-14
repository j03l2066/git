#!/bin/sh
#
# Copyright (c) 2010, Will Palmer
# Copyright (c) 2011, Alexey Shumkin (+ non-UTF-8 commit encoding tests)
#

test_description='Test pretty formats'
. ./test-lib.sh

# Tested non-UTF-8 encoding
test_encoding="ISO8859-1"

sample_utf8_part=$(printf "f\303\244ng")

commit_msg () {
	# String "initial. initial" partly in German
	# (translated with Google Translate),
	# encoded in UTF-8, used as a commit log message below.
	msg="initial. an${sample_utf8_part}lich\n"
	if test -n "$1"
	then
		printf "$msg" | iconv -f utf-8 -t "$1"
	else
		printf "$msg"
	fi
}

test_expect_success 'set up basic repos' '
	>foo &&
	>bar &&
	git add foo &&
	test_tick &&
	git config i18n.commitEncoding $test_encoding &&
	commit_msg $test_encoding | git commit -F - &&
	git add bar &&
	test_tick &&
	git commit -m "add bar" &&
	git config --unset i18n.commitEncoding
'

test_expect_success 'alias builtin format' '
	git log --pretty=oneline >expected &&
	git config pretty.test-alias oneline &&
	git log --pretty=test-alias >actual &&
	test_cmp expected actual
'

test_expect_success 'alias masking builtin format' '
	git log --pretty=oneline >expected &&
	git config pretty.oneline "%H" &&
	git log --pretty=oneline >actual &&
	test_cmp expected actual
'

test_expect_success 'alias user-defined format' '
	git log --pretty="format:%h" >expected &&
	git config pretty.test-alias "format:%h" &&
	git log --pretty=test-alias >actual &&
	test_cmp expected actual
'

test_expect_success 'alias user-defined tformat with %s (ISO8859-1 encoding)' '
	git config i18n.logOutputEncoding $test_encoding &&
	git log --oneline >expected-s &&
	git log --pretty="tformat:%h %s" >actual-s &&
	git config --unset i18n.logOutputEncoding &&
	test_cmp expected-s actual-s
'

test_expect_success 'alias user-defined tformat with %s (utf-8 encoding)' '
	git log --oneline >expected-s &&
	git log --pretty="tformat:%h %s" >actual-s &&
	test_cmp expected-s actual-s
'

test_expect_success 'alias user-defined tformat' '
	git log --pretty="tformat:%h" >expected &&
	git config pretty.test-alias "tformat:%h" &&
	git log --pretty=test-alias >actual &&
	test_cmp expected actual
'

test_expect_success 'alias non-existent format' '
	git config pretty.test-alias format-that-will-never-exist &&
	test_must_fail git log --pretty=test-alias
'

test_expect_success 'alias of an alias' '
	git log --pretty="tformat:%h" >expected &&
	git config pretty.test-foo "tformat:%h" &&
	git config pretty.test-bar test-foo &&
	git log --pretty=test-bar >actual && test_cmp expected actual
'

test_expect_success 'alias masking an alias' '
	git log --pretty=format:"Two %H" >expected &&
	git config pretty.duplicate "format:One %H" &&
	git config --add pretty.duplicate "format:Two %H" &&
	git log --pretty=duplicate >actual &&
	test_cmp expected actual
'

test_expect_success 'alias loop' '
	git config pretty.test-foo test-bar &&
	git config pretty.test-bar test-foo &&
	test_must_fail git log --pretty=test-foo
'

test_expect_success 'NUL separation' '
	printf "add bar\0$(commit_msg)" >expected &&
	git log -z --pretty="format:%s" >actual &&
	test_cmp expected actual
'

test_expect_success 'NUL termination' '
	printf "add bar\0$(commit_msg)\0" >expected &&
	git log -z --pretty="tformat:%s" >actual &&
	test_cmp expected actual
'

test_expect_success 'NUL separation with --stat' '
	stat0_part=$(git diff --stat HEAD^ HEAD) &&
	stat1_part=$(git diff-tree --no-commit-id --stat --root HEAD^) &&
	printf "add bar\n$stat0_part\n\0$(commit_msg)\n$stat1_part\n" >expected &&
	git log -z --stat --pretty="format:%s" >actual &&
	test_cmp expected actual
'

test_expect_failure 'NUL termination with --stat' '
	stat0_part=$(git diff --stat HEAD^ HEAD) &&
	stat1_part=$(git diff-tree --no-commit-id --stat --root HEAD^) &&
	printf "add bar\n$stat0_part\n\0$(commit_msg)\n$stat1_part\n0" >expected &&
	git log -z --stat --pretty="tformat:%s" >actual &&
	test_cmp expected actual
'

for p in short medium full fuller email raw
do
	test_expect_success "NUL termination with --reflog --pretty=$p" '
		revs="$(git rev-list --reflog)" &&
		for r in $revs
		do
			git show -s "$r" --pretty="$p" &&
			printf "\0" || return 1
		done >expect &&
		{
			git log -z --reflog --pretty="$p" &&
			printf "\0"
		} >actual &&
		test_cmp expect actual
	'
done

test_expect_success 'NUL termination with --reflog --pretty=oneline' '
	revs="$(git rev-list --reflog)" &&
	for r in $revs
	do
		git show -s --pretty=oneline "$r" >raw &&
		cat raw | lf_to_nul || exit 1
	done >expect &&
	# the trailing NUL is already produced so we do not need to
	# output another one
	git log -z --pretty=oneline --reflog >actual &&
	test_cmp expect actual
'

test_expect_success 'setup more commits' '
	test_commit "message one" one one message-one &&
	test_commit "message two" two two message-two &&
	head1=$(git rev-parse --verify --short HEAD~0) &&
	head2=$(git rev-parse --verify --short HEAD~1) &&
	head3=$(git rev-parse --verify --short HEAD~2) &&
	head4=$(git rev-parse --verify --short HEAD~3)
'

test_expect_success 'left alignment formatting' '
	git log --pretty="tformat:%<(40)%s" >actual &&
	qz_to_tab_space <<-EOF >expected &&
	message two                            Z
	message one                            Z
	add bar                                Z
	$(commit_msg)                    Z
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%<(40)%s" >actual &&
	qz_to_tab_space <<-EOF | iconv -f utf-8 -t $test_encoding >expected &&
	message two                            Z
	message one                            Z
	add bar                                Z
	$(commit_msg)                    Z
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting at the nth column' '
	git log --pretty="tformat:%h %<|(40)%s" >actual &&
	qz_to_tab_space <<-EOF >expected &&
	$head1 message two                    Z
	$head2 message one                    Z
	$head3 add bar                        Z
	$head4 $(commit_msg)            Z
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting at the nth column' '
	COLUMNS=50 git log --pretty="tformat:%h %<|(-10)%s" >actual &&
	qz_to_tab_space <<-EOF >expected &&
	$head1 message two                    Z
	$head2 message one                    Z
	$head3 add bar                        Z
	$head4 $(commit_msg)            Z
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting at the nth column. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%h %<|(40)%s" >actual &&
	qz_to_tab_space <<-EOF | iconv -f utf-8 -t $test_encoding >expected &&
	$head1 message two                    Z
	$head2 message one                    Z
	$head3 add bar                        Z
	$head4 $(commit_msg)            Z
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting with no padding' '
	git log --pretty="tformat:%<(1)%s" >actual &&
	cat <<-EOF >expected &&
	message two
	message one
	add bar
	$(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting with no padding. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%<(1)%s" >actual &&
	cat <<-EOF | iconv -f utf-8 -t $test_encoding >expected &&
	message two
	message one
	add bar
	$(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting with trunc' '
	git log --pretty="tformat:%<(10,trunc)%s" >actual &&
	qz_to_tab_space <<-\EOF >expected &&
	message ..
	message ..
	add bar  Z
	initial...
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting with trunc. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%<(10,trunc)%s" >actual &&
	qz_to_tab_space <<-\EOF | iconv -f utf-8 -t $test_encoding >expected &&
	message ..
	message ..
	add bar  Z
	initial...
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting with ltrunc' '
	git log --pretty="tformat:%<(10,ltrunc)%s" >actual &&
	qz_to_tab_space <<-EOF >expected &&
	..sage two
	..sage one
	add bar  Z
	..${sample_utf8_part}lich
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting with ltrunc. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%<(10,ltrunc)%s" >actual &&
	qz_to_tab_space <<-EOF | iconv -f utf-8 -t $test_encoding >expected &&
	..sage two
	..sage one
	add bar  Z
	..${sample_utf8_part}lich
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting with mtrunc' '
	git log --pretty="tformat:%<(10,mtrunc)%s" >actual &&
	qz_to_tab_space <<-\EOF >expected &&
	mess.. two
	mess.. one
	add bar  Z
	init..lich
	EOF
	test_cmp expected actual
'

test_expect_success 'left alignment formatting with mtrunc. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%<(10,mtrunc)%s" >actual &&
	qz_to_tab_space <<-\EOF | iconv -f utf-8 -t $test_encoding >expected &&
	mess.. two
	mess.. one
	add bar  Z
	init..lich
	EOF
	test_cmp expected actual
'

test_expect_success 'right alignment formatting' '
	git log --pretty="tformat:%>(40)%s" >actual &&
	qz_to_tab_space <<-EOF >expected &&
	Z                            message two
	Z                            message one
	Z                                add bar
	Z                    $(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'right alignment formatting. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%>(40)%s" >actual &&
	qz_to_tab_space <<-EOF | iconv -f utf-8 -t $test_encoding >expected &&
	Z                            message two
	Z                            message one
	Z                                add bar
	Z                    $(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'right alignment formatting at the nth column' '
	git log --pretty="tformat:%h %>|(40)%s" >actual &&
	qz_to_tab_space <<-EOF >expected &&
	$head1                      message two
	$head2                      message one
	$head3                          add bar
	$head4              $(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'right alignment formatting at the nth column' '
	COLUMNS=50 git log --pretty="tformat:%h %>|(-10)%s" >actual &&
	qz_to_tab_space <<-EOF >expected &&
	$head1                      message two
	$head2                      message one
	$head3                          add bar
	$head4              $(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'right alignment formatting at the nth column. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%h %>|(40)%s" >actual &&
	qz_to_tab_space <<-EOF | iconv -f utf-8 -t $test_encoding >expected &&
	$head1                      message two
	$head2                      message one
	$head3                          add bar
	$head4              $(commit_msg)
	EOF
	test_cmp expected actual
'

# Note: Space between 'message' and 'two' should be in the same column
# as in previous test.
test_expect_success 'right alignment formatting at the nth column with --graph. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --graph --pretty="tformat:%h %>|(40)%s" >actual &&
	iconv -f utf-8 -t $test_encoding >expected <<-EOF &&
	* $head1                    message two
	* $head2                    message one
	* $head3                        add bar
	* $head4            $(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'right alignment formatting with no padding' '
	git log --pretty="tformat:%>(1)%s" >actual &&
	cat <<-EOF >expected &&
	message two
	message one
	add bar
	$(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'right alignment formatting with no padding and with --graph' '
	git log --graph --pretty="tformat:%>(1)%s" >actual &&
	cat <<-EOF >expected &&
	* message two
	* message one
	* add bar
	* $(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'right alignment formatting with no padding. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%>(1)%s" >actual &&
	cat <<-EOF | iconv -f utf-8 -t $test_encoding >expected &&
	message two
	message one
	add bar
	$(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'center alignment formatting' '
	git log --pretty="tformat:%><(40)%s" >actual &&
	qz_to_tab_space <<-EOF >expected &&
	Z             message two              Z
	Z             message one              Z
	Z               add bar                Z
	Z         $(commit_msg)          Z
	EOF
	test_cmp expected actual
'

test_expect_success 'center alignment formatting. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%><(40)%s" >actual &&
	qz_to_tab_space <<-EOF | iconv -f utf-8 -t $test_encoding >expected &&
	Z             message two              Z
	Z             message one              Z
	Z               add bar                Z
	Z         $(commit_msg)          Z
	EOF
	test_cmp expected actual
'
test_expect_success 'center alignment formatting at the nth column' '
	git log --pretty="tformat:%h %><|(40)%s" >actual &&
	qz_to_tab_space <<-EOF >expected &&
	$head1           message two          Z
	$head2           message one          Z
	$head3             add bar            Z
	$head4       $(commit_msg)      Z
	EOF
	test_cmp expected actual
'

test_expect_success 'center alignment formatting at the nth column' '
	COLUMNS=70 git log --pretty="tformat:%h %><|(-30)%s" >actual &&
	qz_to_tab_space <<-EOF >expected &&
	$head1           message two          Z
	$head2           message one          Z
	$head3             add bar            Z
	$head4       $(commit_msg)      Z
	EOF
	test_cmp expected actual
'

test_expect_success 'center alignment formatting at the nth column. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%h %><|(40)%s" >actual &&
	qz_to_tab_space <<-EOF | iconv -f utf-8 -t $test_encoding >expected &&
	$head1           message two          Z
	$head2           message one          Z
	$head3             add bar            Z
	$head4       $(commit_msg)      Z
	EOF
	test_cmp expected actual
'

test_expect_success 'center alignment formatting with no padding' '
	git log --pretty="tformat:%><(1)%s" >actual &&
	cat <<-EOF >expected &&
	message two
	message one
	add bar
	$(commit_msg)
	EOF
	test_cmp expected actual
'

# save HEAD's SHA-1 digest (with no abbreviations) to use it below
# as far as the next test amends HEAD
old_head1=$(git rev-parse --verify HEAD~0)
test_expect_success 'center alignment formatting with no padding. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%><(1)%s" >actual &&
	cat <<-EOF | iconv -f utf-8 -t $test_encoding >expected &&
	message two
	message one
	add bar
	$(commit_msg)
	EOF
	test_cmp expected actual
'

test_expect_success 'left/right alignment formatting with stealing' '
	git commit --amend -m short --author "long long long <long@me.com>" &&
	git log --pretty="tformat:%<(10,trunc)%s%>>(10,ltrunc)% an" >actual &&
	cat <<-\EOF >expected &&
	short long  long long
	message ..   A U Thor
	add bar      A U Thor
	initial...   A U Thor
	EOF
	test_cmp expected actual
'
test_expect_success 'left/right alignment formatting with stealing. i18n.logOutputEncoding' '
	git -c i18n.logOutputEncoding=$test_encoding log --pretty="tformat:%<(10,trunc)%s%>>(10,ltrunc)% an" >actual &&
	cat <<-\EOF | iconv -f utf-8 -t $test_encoding >expected &&
	short long  long long
	message ..   A U Thor
	add bar      A U Thor
	initial...   A U Thor
	EOF
	test_cmp expected actual
'

test_expect_success 'strbuf_utf8_replace() not producing NUL' '
	git log --color --pretty="tformat:%<(10,trunc)%s%>>(10,ltrunc)%C(auto)%d" |
		test_decode_color |
		nul_to_q >actual &&
	! grep Q actual
'

# --date=[XXX] and corresponding %a[X] %c[X] format equivalency
test_expect_success '--date=iso-strict %ad%cd is the same as %aI%cI' '
	git log --format=%ad%n%cd --date=iso-strict >expected &&
	git log --format=%aI%n%cI >actual &&
	test_cmp expected actual
'

test_expect_success '--date=short %ad%cd is the same as %as%cs' '
	git log --format=%ad%n%cd --date=short >expected &&
	git log --format=%as%n%cs >actual &&
	test_cmp expected actual
'

test_expect_success '--date=human %ad%cd is the same as %ah%ch' '
	git log --format=%ad%n%cd --date=human >expected &&
	git log --format=%ah%n%ch >actual &&
	test_cmp expected actual
'

# get new digests (with no abbreviations)
test_expect_success 'set up log decoration tests' '
	head1=$(git rev-parse --verify HEAD~0) &&
	head2=$(git rev-parse --verify HEAD~1)
'

test_expect_success 'log decoration properly follows tag chain' '
	git tag -a tag1 -m tag1 &&
	git tag -a tag2 -m tag2 tag1 &&
	git tag -d tag1 &&
	git commit --amend -m shorter &&
	git log --no-walk --tags --pretty="%H %d" --decorate=full >actual &&
	cat <<-EOF >expected &&
	$head2  (tag: refs/tags/message-one)
	$old_head1  (tag: refs/tags/message-two)
	$head1  (tag: refs/tags/tag2)
	EOF
	sort -k3 actual >actual1 &&
	test_cmp expected actual1
'

test_expect_success 'clean log decoration' '
	git log --no-walk --tags --pretty="%H %D" --decorate=full >actual &&
	cat >expected <<-EOF &&
	$head2 tag: refs/tags/message-one
	$old_head1 tag: refs/tags/message-two
	$head1 tag: refs/tags/tag2
	EOF
	sort -k3 actual >actual1 &&
	test_cmp expected actual1
'

cat >trailers <<EOF
Signed-off-by: A U Thor <author@example.com>
Acked-by: A U Thor <author@example.com>
[ v2 updated patch description ]
Signed-off-by: A U Thor
  <author@example.com>
EOF

unfold () {
	perl -0pe 's/\n\s+/ /g'
}

test_expect_success 'set up trailer tests' '
	echo "Some contents" >trailerfile &&
	git add trailerfile &&
	git commit -F - <<-EOF
	trailers: this commit message has trailers

	This commit is a test commit with trailers at the end. We parse this
	message and display the trailers using %(trailers).

	$(cat trailers)
	EOF
'

test_expect_success 'pretty format %(trailers) shows trailers' '
	git log --no-walk --pretty="%(trailers)" >actual &&
	{
		cat trailers &&
		echo
	} >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:) enables no options' '
	git log --no-walk --pretty="%(trailers:)" >actual &&
	# "expect" the same as the test above
	test_cmp expect actual
'

test_expect_success '%(trailers:only) shows only "key: value" trailers' '
	git log --no-walk --pretty="%(trailers:only)" >actual &&
	{
		grep -v patch.description <trailers &&
		echo
	} >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:only=yes) shows only "key: value" trailers' '
	git log --no-walk --pretty=format:"%(trailers:only=yes)" >actual &&
	grep -v patch.description <trailers >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:only=no) shows all trailers' '
	git log --no-walk --pretty=format:"%(trailers:only=no)" >actual &&
	cat trailers >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:only=no,only=true) shows only "key: value" trailers' '
	git log --no-walk --pretty=format:"%(trailers:only=yes)" >actual &&
	grep -v patch.description <trailers >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:unfold) unfolds trailers' '
	git log --no-walk --pretty="%(trailers:unfold)" >actual &&
	{
		unfold <trailers &&
		echo
	} >expect &&
	test_cmp expect actual
'

test_expect_success ':only and :unfold work together' '
	git log --no-walk --pretty="%(trailers:only,unfold)" >actual &&
	git log --no-walk --pretty="%(trailers:unfold,only)" >reverse &&
	test_cmp actual reverse &&
	{
		grep -v patch.description <trailers | unfold &&
		echo
	} >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:key=foo) shows that trailer' '
	git log --no-walk --pretty="format:%(trailers:key=Acked-by)" >actual &&
	echo "Acked-by: A U Thor <author@example.com>" >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:key=foo) is case insensitive' '
	git log --no-walk --pretty="format:%(trailers:key=AcKed-bY)" >actual &&
	echo "Acked-by: A U Thor <author@example.com>" >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:key=foo:) trailing colon also works' '
	git log --no-walk --pretty="format:%(trailers:key=Acked-by:)" >actual &&
	echo "Acked-by: A U Thor <author@example.com>" >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:key=foo) multiple keys' '
	git log --no-walk --pretty="format:%(trailers:key=Acked-by:,key=Signed-off-By)" >actual &&
	grep -v patch.description <trailers >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:key=nonexistent) becomes empty' '
	git log --no-walk --pretty="x%(trailers:key=Nacked-by)x" >actual &&
	echo "xx" >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:key=foo) handles multiple lines even if folded' '
	git log --no-walk --pretty="format:%(trailers:key=Signed-Off-by)" >actual &&
	grep -v patch.description <trailers | grep -v Acked-by >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:key=foo,unfold) properly unfolds' '
	git log --no-walk --pretty="format:%(trailers:key=Signed-Off-by,unfold)" >actual &&
	unfold <trailers | grep Signed-off-by >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:key=foo,only=no) also includes nontrailer lines' '
	git log --no-walk --pretty="format:%(trailers:key=Acked-by,only=no)" >actual &&
	{
		echo "Acked-by: A U Thor <author@example.com>" &&
		grep patch.description <trailers
	} >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:key) without value is error' '
	git log --no-walk --pretty="tformat:%(trailers:key)" >actual &&
	echo "%(trailers:key)" >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:keyonly) shows only keys' '
	git log --no-walk --pretty="format:%(trailers:keyonly)" >actual &&
	test_write_lines \
		"Signed-off-by" \
		"Acked-by" \
		"[ v2 updated patch description ]" \
		"Signed-off-by" >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:key=foo,keyonly) shows only key' '
	git log --no-walk --pretty="format:%(trailers:key=Acked-by,keyonly)" >actual &&
	echo "Acked-by" >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:key=foo,valueonly) shows only value' '
	git log --no-walk --pretty="format:%(trailers:key=Acked-by,valueonly)" >actual &&
	echo "A U Thor <author@example.com>" >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:valueonly) shows only values' '
	git log --no-walk --pretty="format:%(trailers:valueonly)" >actual &&
	test_write_lines \
		"A U Thor <author@example.com>" \
		"A U Thor <author@example.com>" \
		"[ v2 updated patch description ]" \
		"A U Thor" \
		"  <author@example.com>" >expect &&
	test_cmp expect actual
'

test_expect_success '%(trailers:key=foo,keyonly,valueonly) shows nothing' '
	git log --no-walk --pretty="format:%(trailers:key=Acked-by,keyonly,valueonly)" >actual &&
	echo >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:separator) changes separator' '
	git log --no-walk --pretty=format:"X%(trailers:separator=%x00)X" >actual &&
	(
		printf "XSigned-off-by: A U Thor <author@example.com>\0" &&
		printf "Acked-by: A U Thor <author@example.com>\0" &&
		printf "[ v2 updated patch description ]\0" &&
		printf "Signed-off-by: A U Thor\n  <author@example.com>X"
	) >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:separator=X,unfold) changes separator' '
	git log --no-walk --pretty=format:"X%(trailers:separator=%x00,unfold)X" >actual &&
	(
		printf "XSigned-off-by: A U Thor <author@example.com>\0" &&
		printf "Acked-by: A U Thor <author@example.com>\0" &&
		printf "[ v2 updated patch description ]\0" &&
		printf "Signed-off-by: A U Thor <author@example.com>X"
	) >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:key_value_separator) changes key-value separator' '
	git log --no-walk --pretty=format:"X%(trailers:key_value_separator=%x00)X" >actual &&
	(
		printf "XSigned-off-by\0A U Thor <author@example.com>\n" &&
		printf "Acked-by\0A U Thor <author@example.com>\n" &&
		printf "[ v2 updated patch description ]\n" &&
		printf "Signed-off-by\0A U Thor\n  <author@example.com>\nX"
	) >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:key_value_separator,unfold) changes key-value separator' '
	git log --no-walk --pretty=format:"X%(trailers:key_value_separator=%x00,unfold)X" >actual &&
	(
		printf "XSigned-off-by\0A U Thor <author@example.com>\n" &&
		printf "Acked-by\0A U Thor <author@example.com>\n" &&
		printf "[ v2 updated patch description ]\n" &&
		printf "Signed-off-by\0A U Thor <author@example.com>\nX"
	) >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers:separator,key_value_separator) changes both separators' '
	git log --no-walk --pretty=format:"%(trailers:separator=%x00,key_value_separator=%x00%x00,unfold)" >actual &&
	(
		printf "Signed-off-by\0\0A U Thor <author@example.com>\0" &&
		printf "Acked-by\0\0A U Thor <author@example.com>\0" &&
		printf "[ v2 updated patch description ]\0" &&
		printf "Signed-off-by\0\0A U Thor <author@example.com>"
	) >expect &&
	test_cmp expect actual
'

test_expect_success 'pretty format %(trailers) combining separator/key/keyonly/valueonly' '
	git commit --allow-empty -F - <<-\EOF &&
	Important fix

	The fix is explained here

	Closes: #1234
	EOF

	git commit --allow-empty -F - <<-\EOF &&
	Another fix

	The fix is explained here

	Closes: #567
	Closes: #890
	EOF

	git commit --allow-empty -F - <<-\EOF &&
	Does not close any tickets
	EOF

	git log --pretty="%s% (trailers:separator=%x2c%x20,key=Closes,valueonly)" HEAD~3.. >actual &&
	test_write_lines \
		"Does not close any tickets" \
		"Another fix #567, #890" \
		"Important fix #1234" >expect &&
	test_cmp expect actual &&

	git log --pretty="%s% (trailers:separator=%x2c%x20,key=Closes,keyonly)" HEAD~3.. >actual &&
	test_write_lines \
		"Does not close any tickets" \
		"Another fix Closes, Closes" \
		"Important fix Closes" >expect &&
	test_cmp expect actual
'

test_expect_success 'trailer parsing not fooled by --- line' '
	git commit --allow-empty -F - <<-\EOF &&
	this is the subject

	This is the body. The message has a "---" line which would confuse a
	message+patch parser. But here we know we have only a commit message,
	so we get it right.

	trailer: wrong
	---
	This is more body.

	trailer: right
	EOF

	{
		echo "trailer: right" &&
		echo
	} >expect &&
	git log --no-walk --format="%(trailers)" >actual &&
	test_cmp expect actual
'

test_expect_success 'set up %S tests' '
	git checkout --orphan source-a &&
	test_commit one &&
	test_commit two &&
	git checkout -b source-b HEAD^ &&
	test_commit three
'

test_expect_success 'log --format=%S paints branch names' '
	cat >expect <<-\EOF &&
	source-b
	source-a
	source-b
	EOF
	git log --format=%S source-a source-b >actual &&
	test_cmp expect actual
'

test_expect_success 'log --format=%S paints tag names' '
	git tag -m tagged source-tag &&
	cat >expect <<-\EOF &&
	source-tag
	source-a
	source-tag
	EOF
	git log --format=%S source-tag source-a >actual &&
	test_cmp expect actual
'

test_expect_success 'log --format=%S paints symmetric ranges' '
	cat >expect <<-\EOF &&
	source-b
	source-a
	EOF
	git log --format=%S source-a...source-b >actual &&
	test_cmp expect actual
'

test_expect_success '%S in git log --format works with other placeholders (part 1)' '
	git log --format="source-b %h" source-b >expect &&
	git log --format="%S %h" source-b >actual &&
	test_cmp expect actual
'

test_expect_success '%S in git log --format works with other placeholders (part 2)' '
	git log --format="%h source-b" source-b >expect &&
	git log --format="%h %S" source-b >actual &&
	test_cmp expect actual
'

test_expect_success 'log --pretty=reference' '
	git log --pretty="tformat:%h (%s, %as)" >expect &&
	git log --pretty=reference >actual &&
	test_cmp expect actual
'

test_expect_success 'log --pretty=reference with log.date is overridden by short date' '
	git log --pretty="tformat:%h (%s, %as)" >expect &&
	test_config log.date rfc &&
	git log --pretty=reference >actual &&
	test_cmp expect actual
'

test_expect_success 'log --pretty=reference with explicit date overrides short date' '
	git log --date=rfc --pretty="tformat:%h (%s, %ad)" >expect &&
	git log --date=rfc --pretty=reference >actual &&
	test_cmp expect actual
'

test_expect_success 'log --pretty=reference is never unabbreviated' '
	git log --pretty="tformat:%h (%s, %as)" >expect &&
	git log --no-abbrev-commit --pretty=reference >actual &&
	test_cmp expect actual
'

test_expect_success 'log --pretty=reference is never decorated' '
	git log --pretty="tformat:%h (%s, %as)" >expect &&
	git log --decorate=short --pretty=reference >actual &&
	test_cmp expect actual
'

test_expect_success 'log --pretty=reference does not output reflog info' '
	git log --walk-reflogs --pretty="tformat:%h (%s, %as)" >expect &&
	git log --walk-reflogs --pretty=reference >actual &&
	test_cmp expect actual
'

test_expect_success 'log --pretty=reference is colored appropriately' '
	git log --color=always --pretty="tformat:%C(auto)%h (%s, %as)" >expect &&
	git log --color=always --pretty=reference >actual &&
	test_cmp expect actual
'

test_expect_success '%(describe) vs git describe' '
	git log --format="%H" | while read hash
	do
		if desc=$(git describe $hash)
		then
			: >expect-contains-good
		else
			: >expect-contains-bad
		fi &&
		echo "$hash $desc"
	done >expect &&
	test_path_exists expect-contains-good &&
	test_path_exists expect-contains-bad &&

	git log --format="%H %(describe)" >actual 2>err &&
	test_cmp expect actual &&
	test_must_be_empty err
'

test_expect_success '%(describe:match=...) vs git describe --match ...' '
	test_when_finished "git tag -d tag-match" &&
	git tag -a -m tagged tag-match &&
	git describe --match "*-match" >expect &&
	git log -1 --format="%(describe:match=*-match)" >actual &&
	test_cmp expect actual
'

test_expect_success '%(describe:exclude=...) vs git describe --exclude ...' '
	test_when_finished "git tag -d tag-exclude" &&
	git tag -a -m tagged tag-exclude &&
	git describe --exclude "*-exclude" >expect &&
	git log -1 --format="%(describe:exclude=*-exclude)" >actual &&
	test_cmp expect actual
'

test_expect_success '%(describe:tags) vs git describe --tags' '
	test_when_finished "git tag -d tagname" &&
	git tag tagname &&
	git describe --tags >expect &&
	git log -1 --format="%(describe:tags)" >actual &&
	test_cmp expect actual
'

test_expect_success '%(describe:abbrev=...) vs git describe --abbrev=...' '
	test_when_finished "git tag -d tagname" &&
	git tag -a -m tagged tagname &&
	git describe --abbrev=15 >expect &&
	git log -1 --format="%(describe:abbrev=15)" >actual &&
	test_cmp expect actual
'

test_done
