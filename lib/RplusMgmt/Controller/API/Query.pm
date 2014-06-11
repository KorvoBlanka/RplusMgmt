package RplusMgmt::Controller::API::Query;

use Mojo::Base 'Mojolicious::Controller';

use Rplus::Model::AddressObject;
use Rplus::Model::AddressObject::Manager;

use JSON;

sub complete {
    my $self = shift;

    # Can be executed by all users

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
        } else {
            for (qw(одно двух трех четырех пяти шести семи восьми девяти)) {
                my $x = $_.'комнатная';
                if ($x =~ /^\Q$term\E/i) {
                    $vals{$x} = 1;
                }
            }
        }

        my $items = $self->db->dbh->selectall_arrayref(
            "SELECT DISTINCT max(QK.fval) fval FROM query_keywords QK WHERE QK.fval LIKE ? GROUP BY QK.ftype, QK.fkey LIMIT ?",
            {Slice => {}},
            lc($term =~ s/([%_])/\\$1/gr).'%', $limit
        );
        for my $x (@$items) {
            $vals{$x->{fval}} = 1;
        }

        my $addrobj_iter = Rplus::Model::AddressObject::Manager->get_objects_iterator(
            query => [
                [\'lower(name) LIKE ?' => lc($term =~ s/([%_])/\\$1/gr).'%'],
                level => 7,
                curr_status => 0,
                #($self->config->{'default_city_guid'} ? (parent_guid => $self->config->{'default_city_guid'}) : ()),
                parent_guid => $self->config->{'default_city_guid'},
                '!fts' => undef,
            ],
            sort_by => 'code ASC',
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
