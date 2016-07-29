package RplusMgmt::Controller::Remoteimport;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Modern;

use Rplus::Model::Media::Manager;
use Rplus::Model::Realty::Manager;
use Rplus::Model::MediaImportTask::Manager;

use Rplus::Util::Realty qw(put_object);
use Rplus::Util::Mediator qw(add_mediator);

use JSON;
use Mojo::Collection;
use Mojo::UserAgent;
use Mojo::ByteStream;

use Data::Dumper;

no warnings 'experimental::smartmatch';


sub get_task {
    my $self = shift;

    my $source = $self->param('source');
    my $count = $self->param('count');

    my $list = [];

    my $task_iter = Rplus::Model::MediaImportTask::Manager->get_objects_iterator(
        query => [
            source_name => $source,
            delete_date => undef
        ],
        sort_by => 'id DESC',
        limit => $count,
    );
    while (my $task = $task_iter->next) {
        my $x = {
            url => $task->source_url,
        };
        push @{$list}, $x;
        $task->delete_date('now()');
        $task->save;
    }

    return $self->render(json => {state => 'ok', list => $list});
}

sub upload_result {
    my $self = shift;

    my $data_str = $self->param('data');
    my $data = eval $data_str;

    my $photos = $data->{photos};
    my $addr = $data->{addr};

    my $mediator_company = $data->{mediator_company};
    if ($data->{mediator_company}) {
        delete $data->{mediator_company};
    }

    if ($mediator_company) {
        say 'mediator: ' . $mediator_company;
        foreach (@{$data->{'owner_phones'}}) {
            say 'add mediator ' . $_;
            add_mediator($mediator_company, $_);
        }
    }

    say Dumper $data;

    my $id = put_object($data, $self->config);

    return $self->render(json => {state => 'ok', id => $id});
}

1;
