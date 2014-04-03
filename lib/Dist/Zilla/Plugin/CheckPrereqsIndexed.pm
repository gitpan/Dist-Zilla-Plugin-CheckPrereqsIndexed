package Dist::Zilla::Plugin::CheckPrereqsIndexed;
# ABSTRACT: prevent a release if you have prereqs not found on CPAN
$Dist::Zilla::Plugin::CheckPrereqsIndexed::VERSION = '0.011'; # TRIAL
use 5.10.0; # //
use Moose;

#pod =head1 OVERVIEW
#pod
#pod Sometimes, AutoPrereqs is a little overzealous and finds a prereq that you
#pod wrote inline or have in your F<./t> directory.  Although AutoPrereqs should
#pod grow more accurate over time, and avoid these mistakes, it's not perfect right
#pod now.  CheckPrereqsIndexed will check every required package against the CPAN
#pod index to ensure that they're all real, installable packages.
#pod
#pod If any are unknown, it will prompt the user to continue or abort.
#pod
#pod At present, CheckPrereqsIndexed queries CPANIDX, but this behavior is likely to
#pod change or become pluggable in the future.  In the meantime, this makes
#pod releasing while offline impossible... but it was anyway, right?
#pod
#pod =cut

with 'Dist::Zilla::Role::BeforeRelease';

use List::MoreUtils qw(any uniq);

use namespace::autoclean;

sub mvp_multivalue_args { qw(skips) }
sub mvp_aliases { return { skip => 'skips' } }

#pod =attr skips
#pod
#pod This is an arrayref of regular expressions.  Any module names matching
#pod any of these regex will not be checked.  This should only be necessary
#pod if you have a prerequisite that is not available on CPAN (because it's
#pod distributed in some other way).
#pod
#pod =cut

has skips => (
  is      => 'ro',
  isa     => 'ArrayRef[Str]',
  default => sub { [] },
);

sub before_release {
  my ($self) = @_;

  require version;

  my $prereqs_hash  = $self->zilla->prereqs->as_string_hash;

  my @skips = map {; qr/$_/ } @{ $self->skips };

  my $requirements = CPAN::Meta::Requirements->new;

  # first level keys are phase; second level keys are types; we will just merge
  # everything -- rjbs, 2011-08-18
  for my $req_set (map { values %$_ } values %$prereqs_hash) {
    REQ_PKG: for my $pkg (keys %$req_set) {
      next if $pkg eq 'Config'; # special case -- rjbs, 2011-05-20
      next if $pkg eq 'perl';   # special case -- rjbs, 2011-02-05

      next if any { $pkg =~ $_ } @skips;

      my $ver = $req_set->{$pkg};

      $requirements->add_string_requirement($pkg => $ver);
    }
  }

  my @modules = $requirements->required_modules;
  return unless @modules; # no prereqs!?

  require Encode;
  require LWP::UserAgent;
  require JSON;

  my $ua = LWP::UserAgent->new(keep_alive => 1);
  $ua->env_proxy;

  my %missing;
  my %unmet;

  PKG: for my $pkg (sort @modules) {
    my $res = $ua->get("http://cpanidx.org/cpanidx/json/mod/$pkg");
    unless ($res->is_success) {
      $missing{ $pkg } = 1;
      next PKG;
    }

    # JSON wants UTF-8 bytestreams, so we need to re-encode no matter what
    # encoding we got. -- rjbs, 2011-08-18
    my $yaml_octets = Encode::encode_utf8($res->decoded_content);
    my $payload = JSON::->new->decode($yaml_octets);

    unless (@$payload) {
      $missing{ $pkg } = 1;
      next PKG;
    }

    my $indexed_version = version->parse($payload->[0]{mod_vers});
    next PKG if $requirements->accepts_module($pkg, $indexed_version->stringify);

    $unmet{ $pkg } = {
      required => $requirements->requirements_for_module($pkg),
      indexed  => $indexed_version,
    };
  }

  unless (keys %missing or keys %unmet) {
    $self->log("all prereqs appear to be indexed");
    return;
  }

  if (keys %missing) {
    my @missing = sort keys %missing;
    $self->log("the following prereqs could not be found on CPAN: @missing");
  }

  if (keys %unmet) {
    for my $pkg (sort keys %unmet) {
      $self->log([
        "you required %s version %s but CPAN only has version %s",
        $pkg,
        "$unmet{$pkg}{required}",
        "$unmet{$pkg}{indexed}",
      ]);
    }
  }

  return if $self->zilla->chrome->prompt_yn(
    "release despite missing prereqs?",
    { default => 0 }
  );

  $self->log_fatal("aborting release due to apparently unindexed prereqs");
}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

Dist::Zilla::Plugin::CheckPrereqsIndexed - prevent a release if you have prereqs not found on CPAN

=head1 VERSION

version 0.011

=head1 OVERVIEW

Sometimes, AutoPrereqs is a little overzealous and finds a prereq that you
wrote inline or have in your F<./t> directory.  Although AutoPrereqs should
grow more accurate over time, and avoid these mistakes, it's not perfect right
now.  CheckPrereqsIndexed will check every required package against the CPAN
index to ensure that they're all real, installable packages.

If any are unknown, it will prompt the user to continue or abort.

At present, CheckPrereqsIndexed queries CPANIDX, but this behavior is likely to
change or become pluggable in the future.  In the meantime, this makes
releasing while offline impossible... but it was anyway, right?

=head1 ATTRIBUTES

=head2 skips

This is an arrayref of regular expressions.  Any module names matching
any of these regex will not be checked.  This should only be necessary
if you have a prerequisite that is not available on CPAN (because it's
distributed in some other way).

=head1 AUTHOR

Ricardo Signes <rjbs@cpan.org>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2011 by Ricardo Signes.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut
