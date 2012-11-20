package RplusMgmt::Questions;

use Mojo::Base 'Mojolicious::Controller';

use utf8;

use RplusWeb::Model::Question;
use RplusWeb::Model::Question::Manager;

sub index {
    my $self = shift;
    $self->render;
}

#
# Ajax API
#

sub list {
    my $self = shift;

    my $questions = [];
    my $question_iter = RplusWeb::Model::Question::Manager->get_objects_iterator(
        query => [ delete_date => undef ],
        with_objects => ['client'],
        sort_by => 'add_date DESC',
    );
    while (my $q = $question_iter->next) {
        my $x = { map { $_ => (($q->$_)//'') } @{$q->meta->column_names} };
        $x->{'add_date'} = $x->{'add_date'}->strftime('%FT%T%z');
        $x->{'client'} = { map { $_ => $q->client->$_ } ('name', 'phone_num') } if $q->client_id;
        push @$questions, $x;
    }

    $self->render_json($questions);
}

sub get {
    my $self = shift;

    if (my $id = $self->param('id')) {
        my $question_iter = RplusWeb::Model::Question::Manager->get_objects_iterator(query => [ id => $id, delete_date => undef ]);
        if (my $q = $question_iter->next) {
            my $x = { map { $_ => (($q->$_)//'') } @{$q->meta->column_names} };
            return $self->render_json($x);
        }
    }

    $self->render_not_found;
}

sub add {
    my $self = shift;

    my $status = 'failed';
    my $question = RplusWeb::Model::Question->new(
        map { $_ => $self->param($_) } qw(status title question answer)
    );
    if ($question->save) {
        $status = 'success';
    }

    return $self->render_json({status => $status});
}

sub update {
    my $self = shift;

    if (my $id = $self->param('id')) {
        my $status = 'failed';
        my $question_iter = RplusWeb::Model::Question::Manager->get_objects_iterator(query => [ id => $id, delete_date => undef ]);
        if (my $q = $question_iter->next) {
            $q->$_($self->param($_)) for grep { defined $self->param($_) } qw(status title question answer);
            if ($q->save) {
                $status = 'success';
            }
        }
        return $self->render_json({status => $status});
    }

    $self->render_not_found;
}

sub delete {
    my $self = shift;

    if (my $id = $self->param('id')) {
        my $status = 'failed';
        if (RplusWeb::Model::Question::Manager->update_objects(
            set => { delete_date => \"now()" },
            where => [ id => $id, delete_date => undef ]
        )) {
            $status = 'success';
        }
        return $self->render_json({status => $status});
    }

    $self->render_not_found;
}

1;
