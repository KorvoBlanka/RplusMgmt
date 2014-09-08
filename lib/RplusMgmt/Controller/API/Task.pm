package RplusMgmt::Controller::API::Task;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Task;
use Rplus::Model::Task::Manager;

use Mojo::Collection;

use JSON;
use Data::Dumper;

no warnings 'experimental::smartmatch';

sub list {
    my $self = shift;

    my $start_date = $self->param('start_date') || 'any';
    my $end_date = $self->param('end_date') || 'any';

    my $status = $self->param('task_status') || 'all';
    my $assigned_user_id = $self->param('assigned_user_id') || 'all';
    my $task_type_id = $self->param('task_type_id') || 'all';

    # "where" query
    my @query;
    {
        if ($status ne 'all') {
            push @query, status => $status;
        }
        if ($assigned_user_id ne 'all') {
            if ($assigned_user_id eq 'own') {
                push @query, assigned_user_id => $self->stash('user')->{id};
            } else {
                push @query, assigned_user_id => $assigned_user_id;
            }
        }
        if ($task_type_id ne 'all') {
            push @query, task_type_id => $task_type_id;
        }
        if ($start_date ne 'any' && $end_date ne 'any') {
            push @query, dead_line => {gt => $start_date};
            push @query, dead_line => {le => $end_date}
        }
    }

    my $task_iter = Rplus::Model::Task::Manager->get_objects_iterator(
        query => [
            @query,
            delete_date => undef,
        ], 
        sort_by => 'dead_line DESC'
    );

    my $res = {
        count => 0,
        list => [],
    };

    while (my $task = $task_iter->next) {
        my $x = {
            id => $task->id,
            task_type => $task->task_type->name,
            creator_user_id => $task->creator_user_id,
            assigned_user_id => $task->assigned_user_id,
            add_date => $task->assigned_user_id,
            remind_date => $task->remind_date,
            dead_line => $task->dead_line,
            description => $task->description,
            status => $task->status,
            category => $task->task_type->category,
            color => $task->task_type->color,
        };

        push @{$res->{list}}, $x;
    }

    $res->{count} = scalar @{$res->{list}};

    return $self->render(json => $res);
}

sub get_task_count {
    my $self = shift;

    my $start_date = $self->param('start_date') || 'any';
    my $end_date = $self->param('end_date') || 'any';
    my $status = $self->param('task_status') || 'all';
    my $task_type_id = $self->param('task_type_id') || 'all';
    my $agent_id = $self->param('agent_id') || 'all';

    # "where" query
    my @query;
    {
        if ($status ne 'all') {
            push @query, status => $status;
        }
        if ($agent_id ne 'all') {
            push @query, assigned_user_id => $agent_id;
        }
        if ($task_type_id ne 'all') {
            push @query, task_type_id => $task_type_id;
        }
        if ($start_date ne 'any' && $end_date ne 'any') {
            push @query, dead_line => {gt => $start_date};
            push @query, dead_line => {le => $end_date}
        }
    }

    my $task_count = Rplus::Model::Task::Manager->get_objects_count(
        query => [
            @query,
            delete_date => undef,
        ], 
    );

    return $self->render(json => {status => 'success', count => $task_count},);
}

sub get {
    my $self = shift;

    my $id = $self->param('id');
    my $task = Rplus::Model::Task::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $task;

    my $x = {
        id => $task->id,
        task_type_id => $task->task_type_id,
        creator_user_id => $task->creator_user_id,
        assigned_user_id => $task->assigned_user_id,
        add_date => $task->assigned_user_id,
        remind_date => $task->remind_date,
        dead_line => $task->dead_line,
        description => $task->description,
        status => $task->status,
        category => $task->task_type->category,
        color => $task->task_type->color,
    };

    return $self->render(json => {status => 'success', task => $x},);    
}

sub update {
    my $self = shift;

    my $id = $self->param('id');


    my $task = Rplus::Model::Task::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $task;    

    for ($self->param) {
        if ($_ eq 'status') {
            $task->status($self->param('status'));
        } elsif ($_ eq 'dead_line') {
            $task->dead_line($self->param('dead_line'));
        }
    }

    $task->change_date('now()');
    $task->save(changes_only => 1);
    # Not Implemented
    return $self->render(json => {status => 'success', id => $task->id},);
}

sub save {
    my $self = shift;

    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'write');
    my $task_type_id = $self->param('task_type_id');
    my $dead_line = $self->param('dead_line');    
    my $assigned_user_id = $self->param('assigned_user_id');
    my $description = $self->param('description');
    my $client_id = $self->param('client_id');
    my $realty_id = $self->param('realty_id');

    my $creator_user_id = $self->stash('user')->{id};

    my $task;
    if (my $id = $self->param('id')) {
        $task = Rplus::Model::Task::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } else {
        $task = Rplus::Model::Task->new(task_type_id => $task_type_id, creator_user_id => $creator_user_id);
        $task->client_id($client_id);
        $task->realty_id($realty_id);        
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $task;

    $task->assigned_user_id($assigned_user_id);
    $task->description($description);
    $task->dead_line($dead_line);
    $task->save(changes_only => 1);

    return $self->render(json => {status => 'success', id => $task->id});
}

sub delete {
    my $self = shift;

    return $self->render(json => {status => 'success'});
}

sub get_piramid_data {  # вынести всю аналитику в отдельный модуль (realty.get_for_plot)
    my $self = shift;

    my $task_iter = Rplus::Model::Task::Manager->get_objects_iterator(
        query => [
            '!realty_id' => undef,
            task_type_id => [1, 2, 3, 4, 5],
            delete_date => undef,
        ], 
    );

    my %groups = ();
    while (my $task = $task_iter->next) {
        if (exists $groups{$task->realty_id}) {
            if ($groups{$task->realty_id}->{id} < $task->id) {
                $groups{$task->realty_id} = {id => $task->id, task_type_id => $task->task_type_id};
            }
        } else {
            $groups{$task->realty_id} = {id => $task->id, task_type_id => $task->task_type_id};
        }
    }

    my @res = (0,0,0,0);
    while( my ($k, $v) = each %groups ) {
        given ($v->{task_type_id}) {
            when (1) {$res[0] ++;}
            when (2) {$res[0] ++; $res[1] ++;}
            when (3) {$res[0] ++; $res[1] ++; $res[2] ++;}
            when (4) {$res[0] ++; $res[1] ++; $res[2] ++; $res[3] ++;}
            when (5) {$res[0] ++; $res[1] ++; $res[2] ++; $res[3] ++; $res[4] ++;}
        } 
    }

    return $self->render(json => {status => 'success', data => \@res});
}

1;
