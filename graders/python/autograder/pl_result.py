import traceback
import unittest
from code_feedback import GradingComplete, Feedback
from pl_execute import UserCodeFailed
from pl_helpers import print_student_code, DoNotRun


class PrairieTestResult(unittest.TestResult):

    error_message = ('The grading code failed -- sorry about that!\n\n'
                     'This may be an issue with your code.\nIf so, you can '
                     'take a look at the traceback below to help debug.\n'
                     'If you believe this is an issue with the grading code,\n'
                     'please notify the course staff.\n\n'
                     'The error traceback is below:\n')

    major_error_message = ('The grading code was not able to run.\n'
                           'Please notify the course staff '
                           'and include this entire message,\n'
                           'including the traceback below.\n\n'
                           'The error traceback is:\n')

    def __init__(self):
        unittest.TestResult.__init__(self)
        self.results = []
        self.buffer = False #True
        self.done_grading = False

    def startTest(self, test):
        unittest.TestResult.startTest(self, test)
        options = getattr(test, test._testMethodName).__func__.__dict__
        points = options.get('points', 1)
        name = options.get('name', test.shortDescription())

        if name is None:
            name = test._testMethodName
        self.results.append({'name': name, 'max_points': points})

    def addSuccess(self, test):
        unittest.TestResult.addSuccess(self, test)
        if test.points is None:
            self.results[-1]['points'] = self.results[-1]['max_points']
        else:
            self.results[-1]['points'] = (test.points *
                                          self.results[-1]['max_points'])

    def addError(self, test, err):
        if isinstance(err[1], GradingComplete):
            self.done_grading = True
            self.addFailure(test, err)
        elif isinstance(err[1], DoNotRun):
            self.results[-1]['points'] = 0
            self.results[-1]['max_points'] = 0
        elif isinstance(err[1], UserCodeFailed):
            # Student code raised Exception
            tr_list = traceback.format_exception(*err[1].err)
            self.done_grading = True
            self.results.append({'name': 'Your code raised an Exception',
                                 'max_points': 1,
                                 'points': 0})
            Feedback.set_name('Your code raised an Exception')
            Feedback.add_feedback(''.join(tr_list))
            Feedback.add_feedback('\n\nYour code:\n\n')
            print_student_code()
        else:
            tr_list = traceback.format_exception(*err)
            test_id = test.id().split()[0]
            if not test_id.startswith('test'):
                # Error in setup code -- not recoverable
                self.done_grading = True
                self.results = []
                self.results.append({'name': 'Internal Grading Error',
                                     'max_points': 1,
                                     'points': 0})
                Feedback.set_name('Internal Grading Error')
                Feedback.add_feedback(self.major_error_message +
                                      ''.join(tr_list))
            else:
                # Error in a single test -- keep going
                unittest.TestResult.addError(self, test, err)
                self.results[-1]['points'] = 0
                Feedback.add_feedback(self.error_message + ''.join(tr_list))

    def addFailure(self, test, err):
        unittest.TestResult.addFailure(self, test, err)
        if test.points is None:
            self.results[-1]['points'] = 0
        else:
            self.results[-1]['points'] = (test.points *
                                          self.results[-1]['max_points'])

    def stopTest(self, test):
        # Never write output back to the console
        self._mirrorOutput = False
        unittest.TestResult.stopTest(self, test)

    def getResults(self):
        return self.results