package RplusMgmt::Controller::Tasks;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::RuntimeParam;
use Rplus::Model::RuntimeParam::Manager;

use RplusMgmt::Task::SMS;
use RplusMgmt::Task::Subscriptions;
use RplusMgmt::Task::Landmarks;
use RplusMgmt::Task::CalendarSync;

use Mojo::IOLoop;

sub run {
    my $self = shift;

    # Increase inactivity timeout for connection a bit
    Mojo::IOLoop->stream($self->tx->connection)->timeout(6000);

    # Acquire mutex
    my $mutex;
    eval {
        $mutex = Rplus::Model::RuntimeParam->new(key => 'tasks_run_mutex')->load(lock => {type => 'for update', nowait => 1}, speculative => 1);
        if (!$mutex) {
            Rplus::Model::RuntimeParam->new(key => 'tasks_run_mutex')->save; # Create record
            $mutex = Rplus::Model::RuntimeParam->new(key => 'tasks_run_mutex')->load(lock => {type => 'for update', nowait => 1}); # Lock created record
        }
        1;
    } or do {
        return $self->render(json => {status => 'busy'});
    };

    # Execute tasks
    RplusMgmt::Task::Subscriptions->run($self);
    RplusMgmt::Task::SMS->run($self);
    #RplusMgmt::Task::Landmarks->run($self);
    RplusMgmt::Task::CalendarSync->run($self);

    # Update lock
    $mutex->ts('now()');
    $mutex->save(changes_only => 1);

    return $self->render(json => {status => 'success'});
}

1;
