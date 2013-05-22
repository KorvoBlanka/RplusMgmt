package RplusMgmt::Controller::API::Claim;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::Claim;
use Rplus::Model::Claim::Manager;

use Rplus::Object::Realty;
use Rplus::Object::Realty::Manager;

use Rplus::Util qw(format_phone_num);

sub auth {
    my $self = shift;

    my $user_role = $self->session->{'user'}->{'role'};
    if ($user_role && $self->config->{'roles'}->{$user_role}->{'realty'}) {
        return 1;
    }

    $self->render_not_found;
    return undef;
}

sub count {
    my $self = shift;

    my $claims_count = Rplus::Object::Realty::Manager->get_objects_count(query => [
        \"t1.id IN (SELECT CLAIMS.realty_id FROM claims WHERE CLAIMS.status = 'new')",
        'close_date' => undef,
    ]);

    return $self->render_json({'count' => $claims_count});
}

sub list {
    my $self = shift;

    my $realty_id = $self->param('realty_id');
    return $self->render_not_found unless $realty_id;

    my @claims;
    my $claim_iter = Rplus::Model::Claim::Manager->get_objects_iterator(
        query => [
            realty_id => $realty_id,
        ],
        sort_by => 'CASE t1.status WHEN \'new\' THEN -99 WHEN \'confirmed\' THEN -98 WHEN \'rejected\' THEN -97 ELSE 0 END, t1.add_date DESC',
    );
    my $count_new = 0;
    while (my $claim = $claim_iter->next) {
        push @claims, {
            id => $claim->id,
            client => $claim->client->name.', '.(format_phone_num($claim->client->phone_num, 'human') || ''),
            type => $claim->type,
            comment => $claim->comment,
            add_date => $claim->add_date->strftime('%d.%m.%Y'),
            status => $claim->status,
            answer => $claim->answer,
        };
        $count_new++ if $claim->status eq 'new';
    }

    my $res = {
        count => scalar(@claims),
        count_new => $count_new,
        list => \@claims
    };

    $self->render_json($res);
}

sub update {
    my $self = shift;

    my $id = $self->param('id');
    my $status = $self->param('status');
    my $answer = $self->param('answer') || undef;

    return $self->render_json({status => 'failed'}) unless $id;
    return $self->render_json({status => 'failed'}) unless $status eq 'confirmed' || $status eq 'rejected';

    my $claim = Rplus::Model::Claim::Manager->get_objects(query => [ id => $id, status => 'new' ])->[0];
    return $self->render_json({status => 'failed'}) unless $claim;

    $claim->status($status);
    $claim->answer($answer);
    $claim->save;

    $self->render_json({status => 'success'});
}

1;
