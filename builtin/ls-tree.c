/*
 * GIT - The information manager from hell
 *
 * Copyright (C) Linus Torvalds, 2005
 */
#include "cache.h"
#include "config.h"
#include "object-store.h"
#include "blob.h"
#include "tree.h"
#include "commit.h"
#include "quote.h"
#include "builtin.h"
#include "parse-options.h"
#include "pathspec.h"

static int line_termination = '\n';
#define LS_RECURSIVE 1
#define LS_TREE_ONLY (1 << 1)
#define LS_SHOW_TREES (1 << 2)
#define LS_NAME_ONLY (1 << 3)
#define LS_SHOW_SIZE (1 << 4)
#define LS_OBJECT_ONLY (1 << 5)
static int abbrev;
static int ls_options;
static struct pathspec pathspec;
static int chomp_prefix;
static const char *ls_tree_prefix;
static unsigned int shown_bits;
#define SHOW_FILE_NAME 1
#define SHOW_SIZE (1 << 1)
#define SHOW_OBJECT_NAME (1 << 2)
#define SHOW_TYPE (1 << 3)
#define SHOW_MODE (1 << 4)
#define SHOW_DEFAULT 29 /* 11101 size is not shown to output by default */

static const  char * const ls_tree_usage[] = {
	N_("git ls-tree [<options>] <tree-ish> [<path>...]"),
	NULL
};

enum {
	MODE_UNSPECIFIED = 0,
	MODE_NAME_ONLY,
	MODE_OBJECT_ONLY,
	MODE_LONG,
};

static int cmdmode = MODE_UNSPECIFIED;

static int show_recursive(const char *base, int baselen, const char *pathname)
{
	int i;

	if (ls_options & LS_RECURSIVE)
		return 1;

	if (!pathspec.nr)
		return 0;

	for (i = 0; i < pathspec.nr; i++) {
		const char *spec = pathspec.items[i].match;
		int len, speclen;

		if (strncmp(base, spec, baselen))
			continue;
		len = strlen(pathname);
		spec += baselen;
		speclen = strlen(spec);
		if (speclen <= len)
			continue;
		if (spec[len] && spec[len] != '/')
			continue;
		if (memcmp(pathname, spec, len))
			continue;
		return 1;
	}
	return 0;
}

static int show_tree(const struct object_id *oid, struct strbuf *base,
		const char *pathname, unsigned mode, void *context)
{
	int retval = 0;
	int baselen;
	int interspace = 0;
	const char *type = blob_type;

	if (S_ISGITLINK(mode)) {
		/*
		 * Maybe we want to have some recursive version here?
		 *
		 * Something similar to this incomplete example:
		 *
		 * if (show_subprojects(base, baselen, pathname))
		 *	retval = READ_TREE_RECURSIVE;
		 *
		 */
		type = commit_type;
	} else if (S_ISDIR(mode)) {
		if (show_recursive(base->buf, base->len, pathname)) {
			retval = READ_TREE_RECURSIVE;
			if (!(ls_options & LS_SHOW_TREES))
				return retval;
		}
		type = tree_type;
	}
	else if (ls_options & LS_TREE_ONLY)
		return 0;

	if (shown_bits & SHOW_MODE) {
		printf("%06o", mode);
		interspace = 1;
	}
	if (shown_bits & SHOW_TYPE) {
		printf("%s%s", interspace ? " " : "", type);
		interspace = 1;
	}
	if (shown_bits & SHOW_OBJECT_NAME) {
		printf("%s%s", interspace ? " " : "",
		       find_unique_abbrev(oid, abbrev));
		if (!(shown_bits ^ SHOW_OBJECT_NAME))
			goto LINE_FINISH;
		interspace = 1;
	}
	if (shown_bits & SHOW_SIZE) {
		char size_text[24];
		if (!strcmp(type, blob_type)) {
			unsigned long size;
			if (oid_object_info(the_repository, oid, &size) == OBJ_BAD)
				xsnprintf(size_text, sizeof(size_text), "BAD");
			else
				xsnprintf(size_text, sizeof(size_text),
					  "%"PRIuMAX, (uintmax_t)size);
		} else
			xsnprintf(size_text, sizeof(size_text), "-");
		printf("%s%7s", interspace ? " " : "", size_text);
		interspace = 1;
	}
	if (shown_bits & SHOW_FILE_NAME) {
		if (interspace)
			printf("\t");
		baselen = base->len;
		strbuf_addstr(base, pathname);
		write_name_quoted_relative(base->buf,
					   chomp_prefix ? ls_tree_prefix : NULL,
					   stdout,
					   line_termination
					   ? CQ_NO_TERMINATOR_C_QUOTED
					   : CQ_NO_TERMINATOR_AS_IS);
		strbuf_setlen(base, baselen);
	}

LINE_FINISH:
	putchar(line_termination);
	return retval;
}

static int parse_shown_fields(void)
{
	if (cmdmode == MODE_NAME_ONLY) {
		shown_bits = SHOW_FILE_NAME;
		return 0;
	}
	if (cmdmode == MODE_OBJECT_ONLY) {
		shown_bits = SHOW_OBJECT_NAME;
		return 0;
	}
	if (!ls_options || (ls_options & LS_RECURSIVE)
	    || (ls_options & LS_SHOW_TREES)
	    || (ls_options & LS_TREE_ONLY))
		shown_bits = SHOW_DEFAULT;
	if (cmdmode == MODE_LONG)
		shown_bits = SHOW_DEFAULT | SHOW_SIZE;
	return 1;
}

int cmd_ls_tree(int argc, const char **argv, const char *prefix)
{
	struct object_id oid;
	struct tree *tree;
	int i, full_tree = 0;
	const struct option ls_tree_options[] = {
		OPT_BIT('d', NULL, &ls_options, N_("only show trees"),
			LS_TREE_ONLY),
		OPT_BIT('r', NULL, &ls_options, N_("recurse into subtrees"),
			LS_RECURSIVE),
		OPT_BIT('t', NULL, &ls_options, N_("show trees when recursing"),
			LS_SHOW_TREES),
		OPT_SET_INT('z', NULL, &line_termination,
			    N_("terminate entries with NUL byte"), 0),
		OPT_CMDMODE('l', "long", &cmdmode, N_("include object size"),
			    MODE_LONG),
		OPT_CMDMODE(0, "name-only", &cmdmode, N_("list only filenames"),
			    MODE_NAME_ONLY),
		OPT_CMDMODE(0, "name-status", &cmdmode, N_("list only filenames"),
			    MODE_NAME_ONLY),
		OPT_CMDMODE(0, "object-only", &cmdmode, N_("list only objects"),
			    MODE_OBJECT_ONLY),
		OPT_SET_INT(0, "full-name", &chomp_prefix,
			    N_("use full path names"), 0),
		OPT_BOOL(0, "full-tree", &full_tree,
			 N_("list entire tree; not just current directory "
			    "(implies --full-name)")),
		OPT__ABBREV(&abbrev),
		OPT_END()
	};

	git_config(git_default_config, NULL);
	ls_tree_prefix = prefix;
	if (prefix && *prefix)
		chomp_prefix = strlen(prefix);

	argc = parse_options(argc, argv, prefix, ls_tree_options,
			     ls_tree_usage, 0);
	if (full_tree) {
		ls_tree_prefix = prefix = NULL;
		chomp_prefix = 0;
	}
	/* -d -r should imply -t, but -d by itself should not have to. */
	if ( (LS_TREE_ONLY|LS_RECURSIVE) ==
	    ((LS_TREE_ONLY|LS_RECURSIVE) & ls_options))
		ls_options |= LS_SHOW_TREES;

	if (argc < 1)
		usage_with_options(ls_tree_usage, ls_tree_options);
	if (get_oid(argv[0], &oid))
		die("Not a valid object name %s", argv[0]);

	parse_shown_fields();
	/*
	 * show_recursive() rolls its own matching code and is
	 * generally ignorant of 'struct pathspec'. The magic mask
	 * cannot be lifted until it is converted to use
	 * match_pathspec() or tree_entry_interesting()
	 */
	parse_pathspec(&pathspec, PATHSPEC_ALL_MAGIC &
				  ~(PATHSPEC_FROMTOP | PATHSPEC_LITERAL),
		       PATHSPEC_PREFER_CWD,
		       prefix, argv + 1);
	for (i = 0; i < pathspec.nr; i++)
		pathspec.items[i].nowildcard_len = pathspec.items[i].len;
	pathspec.has_wildcard = 0;
	tree = parse_tree_indirect(&oid);
	if (!tree)
		die("not a tree object");
	return !!read_tree(the_repository, tree,
			   &pathspec, show_tree, NULL);
}
