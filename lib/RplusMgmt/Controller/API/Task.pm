package RplusMgmt::Controller::API::Task;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Task;
use Rplus::Model::Task::Manager;

use Rplus::Object::Realty;
use Rplus::Object::Realty::Manager;

use Rplus::Config::Realty;

use Rplus::DB;

my %REALTY_TYPES_H = @Rplus::Config::Realty::REALTY_TYPES;

sub auth {
    my $self = shift;

    my $user_role = $self->session->{'user'}->{'role'};
    if ($user_role && $self->config->{'roles'}->{$user_role}->{'tasks'}) {
        return 1;
    }

    $self->render_not_found;
    return undef;
}

sub notify {
    my $self = shift;

    my $res = {
        list => [],
        count => 0,
    };

    my $task_iter = Rplus::Model::Task::Manager->get_objects_iterator(
        query => [
            type => 'in',
            assigned_user_id => $self->session->{'user'}->{'id'},
            status => 'scheduled',
            delete_date => undef,
            \"deadline_date <= now()",
        ],
        sort_by => 'deadline_date, add_date',
        with_columns => ['creator'],
        limit => 5,
    );
    while (my $task = $task_iter->next) {
        push @{$res->{'list'}}, {
            %{$task->as_tree(max_depth => 0)},

            creator => $task->creator_id ? $task->creator->name : undef,
        };
    }

    $res->{'count'} = @{$res->{'list'}};

    return $self->render_json($res);
}

sub list {
    my $self = shift;

    my $category = $self->param('category');

    my ($start_dt, $end_dt);
    if ($self->param('start_date') =~ /^\d{4}\-\d{2}\-\d{2}$/ && $self->param('end_date') =~ /^\d{4}\-\d{2}\-\d{2}$/) {
        eval {
            $start_dt = DateTime::Format::Pg->parse_datetime($self->param('start_date')." 00:00:00");
            $start_dt->set_time_zone('local');
            $end_dt = DateTime::Format::Pg->parse_datetime($self->param('end_date')." 23:59:59");
            $end_dt->set_time_zone('local');
            1;
        } or do {
            $start_dt = undef;
            $end_dt = undef;
        };
    }

    my $res = {
        in =>  { count => 0, list => [] },
        out => { count => 0, list => [] },
    };

    return $self->render_json($res) unless $start_dt && $end_dt;

    my $task_iter = Rplus::Model::Task::Manager->get_objects_iterator(
        query => [
            or => [
                and => [
                    type => 'in',
                    assigned_user_id => $self->session->{'user'}->{'id'},
                ],
                and => [
                    type => 'out',
                    creator_id => $self->session->{'user'}->{'id'},
                    \"t1.assigned_user_id != t1.creator_id",
                ]
            ],
            delete_date => undef,
            ($category ? (category => $category) : ()),
            or => [
                deadline_date => {ge_le => [$start_dt, $end_dt]},
                and => [
                    \"deadline_date <= now()",
                    status => 'scheduled',
                ]
            ],
        ],
        sort_by => 'type, deadline_date, add_date',
        with_columns => ['creator', 'assigned_user', 'realty'],
    );
    while (my $task = $task_iter->next) {
        push @{$res->{$task->type}->{'list'}}, {
            %{$task->as_tree(max_depth => 0)},

            creator => $task->creator_id ? $task->creator->name : undef,
            assigned_user => $task->assigned_user_id ? $task->assigned_user->name : undef,

            realty => $task->realty_id ? $REALTY_TYPES_H{$task->realty->realty_type} : undef,
        };
        $res->{$task->type}->{'count'}++;
    }

    return $self->render_json($res);
}

sub get {
    my $self = shift;

    my $id = $self->param('id');
    return $self->render_not_found unless $id;

    my $task = Rplus::Model::Task::Manager->get_objects(query => [
        id => $id,
        assigned_user_id => $self->session->{'user'}->{'id'},
        delete_date => undef,
        type => 'in',
    ])->[0];
    return $self->render_not_found unless $task;

    return $self->render_json($task->as_tree(max_depth => 0));
}

sub add {
    my $self = shift;

    my $assigned_user_id = $self->param('assigned_user_id') || $self->session->{'user'}->{'id'};
    my ($deadline_date, $remind_date);
    if ($self->param('deadline_date') =~ /^(\d{4})-(\d{2})-(\d{2})$/) {
        $deadline_date = DateTime::Format::Pg->parse_date("$1-$2-$3");
        $deadline_date->set_time_zone('local');
    }
    if ($self->param('remind_date') =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2})$/) {
        $remind_date = DateTime::Format::Pg->parse_datetime("$1-$2-$3 $4:00");
        $remind_date->set_time_zone('local');
    }
    my ($category, $realty_id);
    if (($category = $self->param('category')) eq 'realty') {
        $realty_id = $self->param('realty_id');
    }
    my $description = $self->param('description');

    my $db = Rplus::DB->new;
    $db->begin_work;
    eval {
        my $task_out = Rplus::Model::Task->new(
            db => $db,
            creator_id => $self->session->{'user'}->{'id'},
            assigned_user_id => $assigned_user_id,
            deadline_date => $deadline_date,
            remind_date => $remind_date,
            description => $description,
            status => 'scheduled',
            realty_id => $realty_id,
            category => $category,
            type => 'out',
        );
        $task_out->save;

        my $task_in = Rplus::Model::Task->new(
            db => $db,
            parent_task_id => $task_out->id,
            creator_id => $self->session->{'user'}->{'id'},
            assigned_user_id => $assigned_user_id,
            deadline_date => $deadline_date,
            remind_date => $remind_date,
            description => $description,
            status => 'scheduled',
            realty_id => $realty_id,
            category => $category,
            type => 'in',
        );
        $task_in->save;

        $task_in->add_message_queue({task_id => $task_in->id, creator_id => $task_in->creator_id, type => 'ta'});
        $task_in->save;

        $db->commit;
        1;
    } or do {
        say $@;
        $db->rollback;
        return $self->render_json({status => 'failed'});
    };

    return $self->render_json({status => 'success'});
}

sub update {
    my $self = shift;

    my $id = $self->param('id');
    return $self->render_json({status => 'failed'}) unless $id;

    my $task = Rplus::Model::Task::Manager->get_objects(query => [
        id => $id,
        assigned_user_id => $self->session->{'user'}->{'id'},
        delete_date => undef,
        type => 'in',
    ])->[0];
    return $self->render_json({status => 'failed'}) unless $task;

    # Unchanged fields: assigned_user_id, category
    my ($deadline_date, $remind_date);
    if ($self->param('deadline_date') =~ /^(\d{4})-(\d{2})-(\d{2})$/) {
        $deadline_date = DateTime::Format::Pg->parse_date("$1-$2-$3");
        $deadline_date->set_time_zone('local');
    }
    if ($self->param('remind_date') =~ /^(\d{4})-(\d{2})-(\d{2}) (\d{2}:\d{2})$/) {
        $remind_date = DateTime::Format::Pg->parse_datetime("$1-$2-$3 $4:00");
        $remind_date->set_time_zone('local');
    }
    my $description = $self->param('description');
    my $status = $self->param('status');

    eval {
        $task->deadline_date($deadline_date);
        $task->remind_date($remind_date);
        $task->description($description);
        $task->status($status);

        # Update status of parent task
        if ($task->parent_task_id) {
            $task->parent_task->status($status);
            $task->parent_task->save;
        }

        $task->save;
    } or do {
        say $@;
        return $self->render_json({status => 'failed'});
    };

    return $self->render_json({status => 'success'});
}

1;
