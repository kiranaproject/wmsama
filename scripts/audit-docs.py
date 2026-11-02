#!/usr/bin/env python3
"""Checks the wmsama documentation against the source it describes.

Documentation rots silently. Every check here corresponds to a drift that has
already happened at least once in this repository:

  - README documented a CLI option that the parser did not accept
    (--button-alignment was in --help and missing from the README table)
  - the findings summary table stopped at WM-17 while the body ran to WM-29
  - WM-20 was marked "not started" in its heading and "documented limitation"
    in its progress log
  - the README cited files and test names that did not exist
  - section numbering jumped from 3 to 5 when "Phase 2" was emptied out

No X server and no build are required: everything is read from the source text.

    python3 scripts/audit-docs.py           # check, non-zero exit on drift
    python3 scripts/audit-docs.py --list    # also list every citation found

Exit status is 0 when consistent, 1 when any check fails.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
README = os.path.join(ROOT, 'README.md')
ROADMAP = os.path.join(ROOT, 'docs', 'roadmap.md')
CLI = os.path.join(ROOT, 'src', 'main', 'pascal', 'wmsama.pas')

# Repositories whose sources may be cited. The roadmap documents findings that
# were fixed in other repos, so a Test* or .pas name is allowed to live there.
SIBLINGS = ['wmsama', 'florialib', 'floria-toolkit', 'shellsama']

# Heading mark -> progress-log statuses that are consistent with it.
STATUS_FOR_MARK = {
    '\u2610': {'open', 'partial'},                      # not started
    '\u25d0': {'partial', 'in progress'},               # in progress
    '\u2611': {'done'},                                 # done
    '\u2298': {'withdrawn', 'rejected', 'deferred', 'limitation'},
}

failures = []
notes = []


def fail(check, msg):
    failures.append((check, msg))


def read(path):
    with open(path, encoding='utf-8') as f:
        return f.read()


# --------------------------------------------------------------- CLI options
def cli_options():
    """Returns (flags_in_help_text, flags_the_parser_accepts)."""
    src = read(CLI)
    help_flags = set(re.findall(r"WriteLn\('  (--[a-z-]+)", src))
    parse_flags = set(re.findall(r"Arg = '(--[a-z-]+)'", src))
    return help_flags, parse_flags


def readme_option_table():
    readme = read(README)
    return set(re.findall(r'^\|\s*`(--[a-z-]+)', readme, re.M))


def check_cli():
    help_flags, parse_flags = cli_options()
    table = readme_option_table()

    if help_flags != parse_flags:
        fail('cli', '--help and the argument parser disagree')
        for f in sorted(help_flags - parse_flags):
            fail('cli', '  in --help but not parsed: %s' % f)
        for f in sorted(parse_flags - help_flags):
            fail('cli', '  parsed but not in --help: %s' % f)

    for f in sorted(help_flags - table):
        fail('cli', 'in --help but undocumented in README: %s' % f)
    for f in sorted(table - help_flags):
        fail('cli', 'documented in README but unknown to --help: %s' % f)

    notes.append('cli options: %d (help), %d (parser), %d (README)'
                 % (len(help_flags), len(parse_flags), len(table)))


# ------------------------------------------------------------ roadmap status
def roadmap_headings():
    """WM-id -> status mark, from '### <mark> WM-xx ...' headings."""
    pairs = re.findall(r'^### ([\u2610\u2611\u25d0\u2298]) (WM-\d+)',
                       read(ROADMAP), re.M)
    return {wid: mark for mark, wid in pairs}


def roadmap_table_ids():
    s = read(ROADMAP)
    table = s.split('## 1. Findings Summary', 1)[-1].split('## 2.', 1)[0]
    return set(re.findall(r'^\| (WM-\d+)', table, re.M))


def roadmap_log_statuses():
    """WM-id -> list of (date, status) in file order (the log is append-only)."""
    out = {}
    for line in read(ROADMAP).splitlines():
        if not line.startswith('| 20'):
            continue
        cells = [c.strip() for c in line.split('|')]
        if len(cells) > 4 and re.fullmatch(r'WM-\d+', cells[2]):
            out.setdefault(cells[2], []).append((cells[1], cells[3].strip('*')))
    return out


def check_roadmap_status():
    heads = roadmap_headings()
    log = roadmap_log_statuses()

    for wid, mark in sorted(heads.items(), key=lambda kv: int(kv[0][3:])):
        rows = log.get(wid)
        if not rows:
            fail('status', '%s has a heading but no progress-log row' % wid)
            continue
        date, status = rows[-1]
        allowed = STATUS_FOR_MARK[mark]
        if status not in allowed:
            fail('status', '%s heading is %s but the last log row (%s) says "%s"; '
                 'expected one of %s'
                 % (wid, mark, date, status, '/'.join(sorted(allowed))))

    notes.append('roadmap statuses: %d headings, %d logged' % (len(heads), len(log)))


def check_roadmap_table():
    heads = set(roadmap_headings())
    table = roadmap_table_ids()
    log = set(roadmap_log_statuses())

    for wid in sorted(heads - table, key=lambda x: int(x[3:])):
        fail('table', '%s is documented but missing from the findings table' % wid)
    for wid in sorted(log - table, key=lambda x: int(x[3:])):
        fail('table', '%s has a progress-log row but no findings-table row' % wid)

    notes.append('findings table: %d rows' % len(table))


def check_section_numbers():
    nums = [int(n) for n in re.findall(r'^## (\d+)\.', read(ROADMAP), re.M)]
    if not nums:
        fail('sections', 'no numbered sections found in the roadmap')
        return
    if nums != list(range(len(nums))):
        fail('sections', 'roadmap section numbering is not contiguous from 0: %s'
             % ' '.join(str(n) for n in nums))
    notes.append('roadmap sections: %d (0..%d)' % (len(nums), max(nums)))


# ------------------------------------------------------- named-code citations
def source_texts():
    texts = []
    for project in SIBLINGS:
        for sub in ('src',):
            base = os.path.join(os.path.dirname(ROOT), project, sub)
            if not os.path.isdir(base):
                continue
            for dirpath, _, files in os.walk(base):
                for name in files:
                    if name.endswith(('.pas', '.inc', '.c', '.h')):
                        path = os.path.join(dirpath, name)
                        try:
                            texts.append(read(path))
                        except (OSError, UnicodeDecodeError):
                            pass
    return texts


def check_citations():
    docs = read(README) + read(ROADMAP)
    corpus = source_texts()
    haystack = '\n'.join(corpus)

    tests = set(re.findall(r'`(Test[A-Za-z0-9_]+)`', docs))
    for name in sorted(tests):
        if not re.search(r'\b%s\b' % re.escape(name), haystack):
            fail('citation', 'test %s is cited but does not exist in any source tree'
                 % name)

    files = set(re.findall(r'`([a-z0-9]+\.[a-z0-9.]*\.pas)`', docs))
    known = set()
    for project in SIBLINGS:
        base = os.path.join(os.path.dirname(ROOT), project, 'src')
        for dirpath, _, names in os.walk(base) if os.path.isdir(base) else []:
            known |= set(names)
    for name in sorted(files):
        if name not in known:
            fail('citation', '%s is cited but does not exist in any source tree'
                 % name)

    notes.append('citations: %d test names, %d .pas files, %d source files scanned'
                 % (len(tests), len(files), len(corpus)))


# ------------------------------------------------------------------- glyphs
def check_glyphs():
    """The docs use no emoji; status marks and box-drawing are deliberate."""
    emoji = re.compile('[\U0001F000-\U0001FAFF\uFE0F\u2705\u274C]')
    for path in (README, ROADMAP):
        s = read(path)
        hits = sorted(set(emoji.findall(s)))
        if hits:
            names = ', '.join('U+%04X' % ord(c) for c in hits)
            fail('glyphs', '%s contains emoji: %s'
                 % (os.path.relpath(path, ROOT), names))


def main():
    listing = '--list' in sys.argv

    check_cli()
    check_roadmap_status()
    check_roadmap_table()
    check_section_numbers()
    check_citations()
    check_glyphs()

    if listing:
        print('== inventory ==')
        for n in notes:
            print('  %s' % n)
        print()

    if failures:
        print('FAILED (%d):' % len(failures))
        current = None
        for check, msg in failures:
            if check != current:
                print('\n  [%s]' % check)
                current = check
            print('    %s' % msg)
        print('\nDocs and code disagree. Fix the docs, or the code if the docs '
              'describe the intended behaviour.')
        return 1

    print('OK: docs match the code.')
    for n in notes:
        print('  %s' % n)
    return 0


if __name__ == '__main__':
    sys.exit(main())
