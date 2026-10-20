"""The required question-first opening is enforced before paid production."""
import copy
import unittest
from common import validate_episode_format


class QuestionFirstFormatTest(unittest.TestCase):
    def setUp(self):
        self.recipe = {'id':'crossroads-007','directQuestion':True,'lines':[
            {'key':'hook','text':'Who goes first?'},
            {'key':'challenge','text':'Three seconds!'}]}

    def test_next_episode_accepts_one_question(self):
        validate_episode_format(self.recipe)
        self.recipe.update(id='crossroads-108',arrowPolicy='exit-lane',participantTypes={'red':'car','blue':'car'},carModels={'red':'hatch','blue':'suv'})
        validate_episode_format(self.recipe)

    def test_rejects_a_statement_before_the_question(self):
        self.recipe['lines'][0]['text']='Look at the signs. Who goes first?'
        with self.assertRaises(SystemExit):validate_episode_format(self.recipe)

    def test_rejects_an_explanation_before_countdown(self):
        self.recipe['lines'].insert(1,{'key':'setup','text':'The red car turns right.'})
        with self.assertRaises(SystemExit):validate_episode_format(self.recipe)

    def test_rejects_missing_direct_question_flag(self):
        self.recipe.pop('directQuestion')
        with self.assertRaises(SystemExit):validate_episode_format(self.recipe)

    def test_distinct_shapes_required_for_new_multi_car_scenes(self):
        self.recipe.update(id='crossroads-008',participantTypes={'red':'car','blue':'car'},carModels={'red':'hatch','blue':'hatch'})
        with self.assertRaises(SystemExit):validate_episode_format(self.recipe)
        self.recipe['carModels']['blue']='suv'
        validate_episode_format(self.recipe)

    def test_tram_is_not_a_second_passenger_car(self):
        self.recipe.update(id='crossroads-008',participantTypes={'red':'car','blue':'tram'},carModels={'red':'hatch'})
        validate_episode_format(self.recipe)

    def test_turn_arrow_policy_is_required_for_next_episodes(self):
        self.recipe.update(id='crossroads-009',participantTypes={'red':'car'},carModels={'red':'hatch'})
        with self.assertRaises(SystemExit):validate_episode_format(self.recipe)
        self.recipe['arrowPolicy']='exit-lane'
        validate_episode_format(self.recipe)

    def test_archived_openings_remain_reproducible(self):
        for number in range(1,7):
            recipe=copy.deepcopy(self.recipe)
            recipe.update(id=f'crossroads-{number:03}',directQuestion=False)
            recipe['lines'].insert(1,{'key':'setup','text':'Archived introduction.'})
            validate_episode_format(recipe)


if __name__=='__main__':unittest.main()
