package RplusMgmt::Controller::API::Query;

use Mojo::Base 'Mojolicious::Controller';

use JSON;

use Rplus::Model::AddressObject;
use Rplus::Model::AddressObject::Manager;
use Rplus::Model::QueryCompletion;
use Rplus::Model::QueryCompletion::Manager;

sub auth {
    my $self = shift;
    return 1;
}

sub complete {
    my $self = shift;

    my $q = $self->param('q') || '';
    my $limit = $self->param('limit') || 10;

    my ($term) = ($q =~ /(\w+)$/);
    return $self->render(json => []) unless $term;

    my (%vals, @res);
    {
        if ($q =~ /((\d+)([^\d]*))$/) {
            my ($term2, $value, $word) = ($1, $2, $3);
            my $prefix = $q =~ s/$term2$//r;

            if ($value > 0 && $value < 10 && ' комнатная' =~ /^\Q$word\E/i) {
                push @res, {value => $prefix.$value.' комнатная'};
            }
            if ($value > 0 && $value < 100000 && ' тыс. руб.' =~ /^\Q$word\E/i) {
                push @res, {value => $prefix.$value.' тыс. руб.'};
            }
            if ($value > 0 && $value < 100 && ' этаж' =~ /^\Q$word\E/i) {
                push @res, {value => $prefix.$value.' этаж'};
            }
            if ($value > 0 && $value < 1000 && ' кв. м.' =~ /^\Q$word\E/i) {
                push @res, {value => $prefix.$value.' кв. м.'};
            }
        }

        my $qc_iter = Rplus::Model::QueryCompletion::Manager->get_objects_iterator(
            query => [value => {like => lc($term =~ s/([%_])/\\$1/gr).'%'}],
            limit => $limit,
        );
        while (my $qc = $qc_iter->next) {
            $vals{$qc->value} = 1;
        }

        my $addrobj_iter = Rplus::Model::AddressObject::Manager->get_objects_iterator(
            query => [
                [\'lower(name) LIKE ?' => lc($term =~ s/([%_])/\\$1/gr).'%'],
                level => 7,
                curr_status => 0,
                ($self->config->{'default_city_guid'} ? (parent_guid => $self->config->{'default_city_guid'}) : ()),
                short_type => ['б-р', 'кв-л', 'пер', 'проезд', 'пр-кт', 'ул', 'ш'],
            ],
            #sort_by => 'level DESC',
            limit => $limit,
        );
        while (my $addrobj = $addrobj_iter->next) {
            $vals{lc($addrobj->name.' '.$addrobj->full_type)} = 1;
        }
    }
    
    for (sort { length($a) <=> length($b) } keys %vals) {
        my $prefix = $q =~ s/$term$//r;
        push @res, {value => $prefix.$_}; 
        last if @res == $limit;
    }

    return $self->render(json => \@res);
}

1;
