package Dist::Zilla::App::Command::weaverconf;
# ABSTRACT: Extract your distribution's Pod::Weaver configuration

use Dist::Zilla::App -command;
use Moose 0.91;
use JSON::Any;
use List::AllUtils qw(first);
use MooseX::Types::Moose qw(Str CodeRef);
use MooseX::Types::Structured 0.20 qw(Map);
use aliased 'Dist::Zilla::App::CommandHelper::weaverconf::SExpGen';
use namespace::autoclean;

=head1 SYNOPSIS

    $ dzil weaverconf
    {
        "collectors" : [
            { "command" : "attr",   "new_command" : "head2" },
            { "command" : "method", "new_command" : "head2" },
            { "command" : "func",   "new_command" : "head2" },
            { "command" : "type",   "new_command" : "head2" }
        ],
        "transformers" : [
            {
                "name" : "Pod::Elemental::Transformer::List",
                "args" : { "format_name" : "list" }
            }
        ]

    }

=head1 DESCRIPTION

This command will extract the Pod::Weaver configuration from a
directory containing a L<Dist::Zilla> distribution.

The results will be serialized in the requested format, and written to
C<STDOUT>.

The option C<-f> or C<--format> may be used to request a particular
output format. The following formats are currently available:

=for :list
* json
the default
* lisp
a plist of lists of plists

=cut

has formatters => (
    traits  => [qw(Hash)],
    isa     => Map[Str, CodeRef],
    lazy    => 1,
    builder => '_build_formatters',
    handles => {
        formatter_for     => 'get',
        has_formatter_for => 'exists',
    },
);

sub _build_formatters {
    my ($self) = @_;
    return {
        lisp => sub { SExpGen->new->visit($_[0]) },
        json => sub { JSON::Any->new->to_json($_[0]) },
    };
}

sub abstract { "extract your dist's Pod::Weaver configuration" }

sub opt_spec {
    [ 'format|f:s' => 'the output format to use. defaults to json' ],
}

sub execute {
    my ($self, $opt, $arg) = @_;
    $self->print(
        $self->format_weaver_config({
            format => (exists $opt->{format} ? $opt->{format} : 'json'),
            config => $self->extract_weaver_config
        }),
    );
    return;
}

sub extract_weaver_config {
    my ($self) = @_;

    my $zilla_weaver = first {
        $_->isa('Dist::Zilla::Plugin::PodWeaver')
    } @{ $self->zilla->plugins};
    exit 1 unless $zilla_weaver;

    my @weaver_plugins = @{ $zilla_weaver->weaver->plugins };

    return {
        collectors => [
            map {
                my $t = $_;
                +{ map {
                    ($_ => $t->$_)
                } qw(command new_command) }
            } grep {
                $_->isa('Pod::Weaver::Section::Collect')
            } @weaver_plugins
        ],
        transformers => [
            map {
                +{
                    name => blessed $_->transformer,
                    args => {
                        $_->transformer->isa('Pod::Elemental::Transformer::List')
                            ? (format_name => $_->transformer->format_name)
                            : ()
                    },
                }
            } grep {
                $_->isa('Pod::Weaver::Plugin::Transformer')
            } @weaver_plugins
        ],
    };
}

sub format_weaver_config {
    my ($self, $args) = @_;

    unless ($self->has_formatter_for($args->{format})) {
        $self->log("No formatter available for " . $args->{format});
        exit 1;
    }

    return $self->formatter_for($args->{format})->($args->{config});
}

sub print {
    my ($self, $formatted) = @_;
    $self->log($formatted);
    return;
}

1;
