package Rplus::Util::Task;

use Rplus::Modern;

use Rplus::Model::Task;
use Rplus::Model::Task::Manager;

use Rplus::Util::GoogleCalendar;

use Mojo::Collection;

use JSON;


sub qcreate {
    my $self = shift;
    my $param = shift;

    my $task_type_id = $param->{'task_type_id'};
    my $assigned_user_id = $param->{'assigned_user_id'};
    my $start_date = $param->{'start_date'};
    my $end_date = $param->{'end_date'};
    my $summary = $param->{'summary'};
    my $description = '';
    my $client_id = $param->{'client_id'};
    my $realty_id = $param->{'realty_id'};

    say $start_date;
    say $end_date;

    my $task = Rplus::Model::Task->new(task_type_id => $task_type_id, creator_user_id => $self->stash('user')->{id});
    $task->client_id($client_id);
    $task->realty_id($realty_id);
    $task->summary($summary);
    $task->description($description);
    $task->start_date($start_date);
    $task->end_date($end_date);
    $task->assigned_user_id($assigned_user_id);

    my $result;
    my $gdata = Rplus::Util::GoogleCalendar::getGoogleData($assigned_user_id);
    if ($gdata->{permission_granted}) {
        my $task_type = Rplus::Model::DictTaskType::Manager->get_objects(query => [id => $task_type_id, delete_date => undef])->[0];

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
    
    $task->save(changes_only => 1);

    return $self->render(json => {status => 'success', id => $task->id, google_id => $task->google_id});    

    return 'success';
}

1;
