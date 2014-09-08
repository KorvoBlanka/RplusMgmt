package RplusMgmt::Controller::API::TaskType;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::DictTaskType::Manager;

use Mojo::Collection;

use JSON;
use Data::Dumper;

no warnings 'experimental::smartmatch';

sub list {
    my $self = shift;

    my $task_types_iter = Rplus::Model::DictTaskType::Manager->get_objects_iterator(query => [delete_date => undef], sort_by => 'id');

    my $res = {
        count => 0,
        list => [],
    };

    while (my $task_type = $task_types_iter->next) {
        my $x = {
            id => $task_type->id,
            name => $task_type->name,
            add_date => $task_type->add_date,
            category => $task_type->category,
            color => $task_type->color,
        };

        push @{$res->{list}}, $x;
    }

    return $self->render(json => $res);
}

sub get {
    my $self = shift;

    # Not Implemented
    return $self->render(json => {error => 'Not Implemented'}, status => 501);
}

sub update {
    my $self = shift;

    # Not Implemented
    return $self->render(json => {error => 'Not Implemented'}, status => 501);
}

sub save {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'write');

    my $name = $self->param('name');
    my $category = $self->param('category') || 'both';
    my $color = $self->param('color') || '#B1D5EB';


    my $task_type;
    if (my $id = $self->param('id')) {
        $task_type = Rplus::Model::DictTaskType::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } else {
        $task_type = Rplus::Model::DictTaskType->new(name => $name);
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $task_type;

    $task_type->name($name);
    $task_type->category($category);
    $task_type->color($color);
    $task_type->save(changes_only => 1);

    return $self->render(json => {status => 'success', task_type => {
            id => $task_type->id,
            name => $task_type->name,
            add_date => $task_type->add_date,
            category => $task_type->category,
            color => $task_type->color,
        }
    });
}

sub delete {
    my $self = shift;

    my $id = $self->param('id');

    my $task_type = Rplus::Model::DictTaskType::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $task_type;

    $task_type->delete_date('now()');
    $task_type->save(changes_only => 1);

    return $self->render(json => {status => 'success', id => $id});
}

1;
