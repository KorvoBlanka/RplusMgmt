package RplusMgmt::Task::Landmarks;

use Rplus::Modern;

use Rplus::Model::Landmark;
use Rplus::Model::Landmark::Manager;

sub run {
    my $class = shift;
    my $c = shift;

    # Select landmarks changed in 15 min of last run time
    my $landmarks_count = Rplus::Model::Landmark::Manager->get_objects_count(query => [
        change_date => {ge => \"(SELECT RP.ts FROM _runtime_params RP WHERE RP.key = 'tasks_run_mutex')"},
    ]);
    if ($landmarks_count) {
        # TODO: Improve this (temporary solution)
        $c->db->dbh->do(q{SELECT _query_keywords_refresh()});
        $c->db->dbh->do(q{
            UPDATE realty R
            SET landmarks = COALESCE((
                SELECT array_agg(L.id) FROM landmarks L WHERE L.delete_date IS NULL AND ST_Covers(L.geodata::geography, R.geocoords)
            ), '{}')
            WHERE R.geocoords IS NOT NULL AND R.delete_date IS NULL AND NOT(R.state_code = 'delete')
        });
    }

    return;
}

1;
