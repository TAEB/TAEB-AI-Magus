package TAEB::AI::Magus::Goal::EnterMinetown;
use Moose;
extends 'TAEB::AI::Magus::Goal';

sub prerequisite_goals { 'EnterMines' }

sub met_when { TAEB->current_level->is_minetown }

1;

