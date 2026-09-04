#!/usr/bin/env perl
use strict;
use warnings;

if (@ARGV != 3) {
  die "usage: merge_menu_jsonc.pl INPUT TEMPLATE OUTPUT\n";
}

my ($input_path, $template_path, $output_path) = @ARGV;

sub read_text {
  my ($path, $fallback) = @_;
  return $fallback unless -e $path;

  open my $fh, '<', $path or die "cannot read $path: $!\n";
  local $/;
  my $text = <$fh>;
  close $fh or die "cannot close $path: $!\n";
  return $text;
}

sub write_text {
  my ($path, $text) = @_;

  open my $fh, '>', $path or die "cannot write $path: $!\n";
  print {$fh} $text or die "cannot write $path: $!\n";
  close $fh or die "cannot close $path: $!\n";
}

sub has_entry {
  my ($text, $id) = @_;
  my $pattern = qr/^\s*"\Q$id\E"\s*:/;

  for my $line (split /\n/, $text, -1) {
    next if $line =~ /^\s*\/\//;
    return 1 if $line =~ $pattern;
  }

  return 0;
}

# Find the closing brace of the root object and the last meaningful character
# before it. The latter lets us add a comma before a trailing // or /* */
# comment without disturbing the user's formatting or comments.
sub root_positions {
  my ($text) = @_;
  my $depth = 0;
  my $root_close = -1;
  my $last_sig = -1;
  my $in_string = 0;
  my $escape = 0;
  my $line_comment = 0;
  my $block_comment = 0;
  my $length = length $text;

  for (my $i = 0; $i < $length; $i++) {
    my $ch = substr($text, $i, 1);
    my $next = $i + 1 < $length ? substr($text, $i + 1, 1) : '';

    if ($line_comment) {
      $line_comment = 0 if $ch eq "\n";
      next;
    }

    if ($block_comment) {
      if ($ch eq '*' && $next eq '/') {
        $block_comment = 0;
        $i++;
      }
      next;
    }

    if ($in_string) {
      if ($escape) {
        $escape = 0;
      } elsif ($ch eq '\\') {
        $escape = 1;
      } elsif ($ch eq '"') {
        $in_string = 0;
        $last_sig = $i if $depth >= 1;
      }
      next;
    }

    if ($ch eq '/' && $next eq '/') {
      $line_comment = 1;
      $i++;
      next;
    }

    if ($ch eq '/' && $next eq '*') {
      $block_comment = 1;
      $i++;
      next;
    }

    if ($ch eq '"') {
      $in_string = 1;
      next;
    }

    if ($ch eq '{') {
      $depth++;
      next;
    }

    if ($ch eq '}') {
      if ($depth == 1) {
        $root_close = $i;
        last;
      }
      die "invalid JSONC object nesting in $input_path\n" if $depth == 0;
      $depth--;
      $last_sig = $i;
      next;
    }

    $last_sig = $i if $depth >= 1 && $ch !~ /\s/;
  }

  die "could not find the root JSONC object in $input_path\n"
    if $root_close < 0 || $depth != 1 || $in_string || $block_comment;

  return ($root_close, $last_sig);
}

my $source = read_text($input_path, "{\n}\n");
my $template = read_text($template_path, undef);

# Apps now discovers JotPin through its desktop entry so it can render the real
# PNG application icon. Remove only the exact static row shipped by older
# JotPin releases; a user-owned row with another action remains untouched.
$source =~ s/^[ \t]*"apps\.jotpin"\s*:\s*\{[^\n]*"action"\s*:\s*"omarchy-shell shell summon dev\.jotpin"[^\n]*\},?[ \t]*(?:\n|\z)//m;

$template =~ s/^\s*\{//s
  or die "menu template is missing its opening object\n";
$template =~ s/\}\s*\z//s
  or die "menu template is missing its closing object\n";
$template =~ s/^\s+//;
$template =~ s/\s+\z//;

# Existing user rows win. This also makes repeated deployment idempotent.
my @managed_ids = ('personal', 'personal.jotpin');
my @missing_ids = grep { !has_entry($source, $_) } @managed_ids;
if (!@missing_ids) {
  write_text($output_path, $source);
  exit 0;
}

# Do not overwrite a user's existing managed rows. The one-line template
# entries are removed individually so upgrades can add only what is missing.
for my $id (@managed_ids) {
  next unless has_entry($source, $id);
  $template =~ s/^[ \t]*"\Q$id\E"[ \t]*:[ \t]*\{[^\n]*\},?[ \t]*(?:\n|\z)//m;
}

my ($root_close, $last_sig) = root_positions($source);
my $last_char = $last_sig >= 0 ? substr($source, $last_sig, 1) : '';

if ($last_sig >= 0 && $last_char ne ',') {
  substr($source, $last_sig + 1, 0, ',');
  $root_close++;
}

my $fragment = "\n$template\n";
substr($source, $root_close, 0, $fragment);

write_text($output_path, $source);

if (-e $input_path) {
  my $mode = (stat($input_path))[2] & 07777;
  chmod $mode, $output_path or die "cannot preserve permissions on $output_path: $!\n";
} else {
  chmod 0644, $output_path or die "cannot set permissions on $output_path: $!\n";
}
