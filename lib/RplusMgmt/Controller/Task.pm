package RplusMgmt::Controller::Task;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use Rplus::DB;

use RplusMgmt::Task::SMS;
use RplusMgmt::Task::Subscription;

use Mojo::IOLoop;

sub run {
    my $self = shift;

    # Increase inactivity timeout for connection a bit
    Mojo::IOLoop->stream($self->tx->connection)->timeout(300);

    my $db = Rplus::DB->new;
    $db->begin_work;

    # Acquire mutex
    my $mutex;
    eval {
        $mutex = Rplus::Model::RuntimeParam->new(key => 'task_run_mutex', db => $db)->load(lock => {type => 'for update', nowait => 1}, speculative => 1);
        if (!$mutex) {
            Rplus::Model::RuntimeParam->new(key => 'task_run_mutex')->save; # Create record
            $mutex = Rplus::Model::RuntimeParam->new(key => 'task_run_mutex', db => $db)->load(lock => {type => 'for update', nowait => 1}); # Lock created record
        }
        1;
    } or do {
        $db->rollback;
        return $self->render(json => 'busy');
    };

    # Execute tasks
    RplusMgmt::Task::Subscription->run($self);

    # Last task
    RplusMgmt::Task::SMS->run($self);

    # Update lock
    Rplus::Model::RuntimeParam::Manager->update_objects(set => {ts => \"now()"}, where => [key => 'task_run_mutex'], db => $db);

    $db->commit;
    return $self->render(json => 'done');
}

1;
