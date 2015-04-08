package RplusMgmt::Controller::API::Task;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Task;
use Rplus::Model::Task::Manager;
use Rplus::Model::User;
use Rplus::Model::User::Manager;

use Rplus::Util::GoogleCalendar;

use Mojo::Collection;

use JSON;
use Data::Dumper;

no warnings 'experimental::smartmatch';

sub list {
    my $self = shift;

    my $acc_id = $self->session('user')->{account_id};

    my $start_date = $self->param('start_date') || 'any';
    my $end_date = $self->param('end_date') || 'any';

    my $changed_since = $self->param('changed_since');

    my $status = $self->param('task_status') || 'all';
    my $assigned_user_id = $self->param('assigned_user_id') || 'all';
    my $task_type_id = $self->param('task_type_id') || 'all';

    # sync with google
    #if ($assigned_user_id eq 'all') {
    #    #Rplus::Util::GoogleCalendar::syncAll($acc_id);
    #} else {
    #    if ($assigned_user_id =~ /^a(\d+)$/) {
    #        my $manager = Rplus::Model::User::Manager->get_objects(query => [id => $1, delete_date => undef])->[0];
    #        if (scalar (@{$manager->subordinate})) {
    #            # Засинхронизировать всех подчиненных
    #            for my $user (@{$manager->subordinate}) {
    #                #Rplus::Util::GoogleCalendar::sync($user->id);
    #            }
    #        }
    #    } else {
    #        #Rplus::Util::GoogleCalendar::sync($assigned_user_id);
    #    }
    #}

    # "where" query
    my @query;
    {
        if ($changed_since) {
            push @query, change_date => {gt => $changed_since};
        }
        if ($status ne 'all') {
            push @query, status => $status;
        }
        if ($assigned_user_id ne 'all') {
            if ($assigned_user_id =~ /^a(\d+)$/) {
                my $manager = Rplus::Model::User::Manager->get_objects(query => [id => $1, delete_date => undef])->[0];
                if (scalar (@{$manager->subordinate})) {
                    push @query, assigned_user_id => [$manager->subordinate];
                } else {
                    push @query, assigned_user_id => 0;
                }
            } else {
                push @query, assigned_user_id => $assigned_user_id;
            }
        } else {
            my @user_ids;
            my $user_iter = Rplus::Model::User::Manager->get_objects_iterator(query => [account_id => $acc_id, delete_date => undef]);
            while (my $user = $user_iter->next) {
                if ($self->session('user')->{role} eq 'top') {
                    if ($user->role ne 'top' || $user->id == $self->session('user')->{id}) {
                        push @user_ids, $user->id;
                    }
                } else {
                    push @user_ids, $user->id;
                }
            }
            push @query, assigned_user_id => [@user_ids];
        }
        if ($task_type_id ne 'all') {
            push @query, task_type_id => $task_type_id;
        }
        if ($start_date ne 'any' && $end_date ne 'any') {
            push @query, start_date => {ge => $start_date};
            push @query, start_date => {le => $end_date}
        }
    }

    my $task_iter = Rplus::Model::Task::Manager->get_objects_iterator (
        query => [
            @query,
            delete_date => undef,
        ], 
        sort_by => 'start_date DESC'
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
            add_date => $task->add_date,
            start_date => $task->start_date,
            end_date => $task->end_date,
            remind_date => $task->remind_date,
            summary => $task->summary,
            description => $task->description,
            status => $task->status,
            category => $task->task_type->category,
            color => $task->task_type->color,
            realty_id => $task->realty_id,
            client_id => $task->client_id,            
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
            push @query, start_date => {gt => $start_date};
            push @query, start_date => {le => $end_date}
        }
    }

    my $task_count = Rplus::Model::Task::Manager->get_objects_count(
        query => [
            @query,
            delete_date => undef,
        ], 
    );

    return $self->render(json => {status => 'success', count => $task_count});
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
        start_date => $task->start_date,
        end_date => $task->end_date,
        summary => $task->summary,
        description => $task->description,
        status => $task->status,
        category => $task->task_type->category,
        color => $task->task_type->color,
        realty_id => $task->realty_id,
        client_id => $task->client_id,
    };

    return $self->render(json => {status => 'success', task => $x},);    
}

sub update {
    my $self = shift;

    my $id = $self->param('id');

    my $task = Rplus::Model::Task::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $task;    

    my $result;

    my $status = $self->param('status');
    my $start_date = $self->param('start_date');
    my $end_date = $self->param('end_date');

    if ($status) {
        $task->status($status);

        if ($task->google_id) {
            my $g_status = '';
            if ($self->param('status') eq 'new') {
                $g_status = 'confirmed';
            } elsif ($self->param('status') eq 'done') {
                $g_status = 'cancelled';
            }

            $result = Rplus::Util::GoogleCalendar::setStatus($task->assigned_user_id, $task->google_id, $g_status);
        }        
    }
    if ($start_date && $end_date) {
        $task->start_date($start_date);
        $task->end_date($end_date);

        if ($task->google_id) {
            $result = Rplus::Util::GoogleCalendar::setStartEndDate($task->assigned_user_id, $task->google_id, $start_date, $end_date);
        }
    }
    say $start_date;
    $task->change_date('now()');
    $task->save(changes_only => 1);
    return $self->render(json => {status => 'success', id => $task->id},);
}

sub save {
    my $self = shift;

    my $acc_id = $self->session('user')->{account_id};
    
    #return $self->render(json => {error => 'Forbidden'}, status => 403) unless $self->has_permission(subscriptions => 'write');
    my $task_type_id = $self->param('task_type_id');
    my $assigned_user_id = $self->param('assigned_user_id');
    my $start_date = $self->param('start_date');    
    my $end_date = $self->param('end_date');
    my $summary = $self->param('summary');
    my $description = $self->param('description');
    my $client_id = $self->param('client_id');
    my $realty_id = $self->param('realty_id');

    my $task;
    if (my $id = $self->param('id')) {
        $task = Rplus::Model::Task::Manager->get_objects(query => [id => $id, delete_date => undef])->[0];
    } else {
        $task = Rplus::Model::Task->new(task_type_id => $task_type_id, creator_user_id => $self->stash('user')->{id});
        $task->client_id($client_id);
        $task->realty_id($realty_id);
    }
    return $self->render(json => {error => 'Not Found'}, status => 404) unless $task;

    my $assigned_user = Rplus::Model::User::Manager->get_objects(query => [id => $assigned_user_id, account_id => $acc_id, delete_date => undef])->[0];
    # если пытаемся назначить задачу пользователю другого агенства, то назначим ее себе
    unless ($assigned_user) {
        $assigned_user_id = $self->stash('user')->{id};
    }
    
    $task->summary($summary);
    $task->description($description);
    $task->start_date($start_date);
    $task->end_date($end_date);

    my $gdata = Rplus::Util::GoogleCalendar::getGoogleData($assigned_user_id);
    if ($gdata->{permission_granted}) {
        my $result;
        my $task_type = Rplus::Model::DictTaskType::Manager->get_objects(query => [id => $task_type_id, delete_date => undef])->[0];
        if ($task->id && $task->google_id) {
            if ($task->assigned_user_id == $assigned_user_id) {     # если исполнитель не изменился, просто внесем изменения
                $result = Rplus::Util::GoogleCalendar::patch($assigned_user_id, $task->google_id, {
                    summary => $task_type->name . ': ' . $summary,
                    description => $description,
                    start_date => $start_date,
                    end_date => $end_date,
                });
            } else {    # если изменился, удалим задачу у старого и назначим новому
                # удалить задачу у старого исполнителя

                # назначить новому
                $result = Rplus::Util::GoogleCalendar::insert($assigned_user_id, {
                    summary => $task_type->name . ': ' . $summary,
                    description => $description,
                    start_date => $start_date,
                    end_date => $end_date,
                });
            }
        } else {
            $result = Rplus::Util::GoogleCalendar::insert($assigned_user_id, {
                summary => $task_type->name . ': ' . $summary,
                description => $description,
                start_date => $start_date,
                end_date => $end_date,
            });
        }
        if ($result->{id}) {
            $task->google_id($result->{id});
        }        
    }

    $task->task_type_id($task_type_id);
    $task->assigned_user_id($assigned_user_id);
    $task->save(changes_only => 1);

    return $self->render(json => {status => 'success', id => $task->id, google_id => $task->google_id});
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
